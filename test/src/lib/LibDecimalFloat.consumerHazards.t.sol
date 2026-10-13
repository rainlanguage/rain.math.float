// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {ExponentUnderflow, ExponentOverflow, DivisionByZero} from "src/error/ErrDecimalFloat.sol";

/// The README's consumer guidance, one test per hazard. Expected values are
/// the exact result rounded toward zero to the nearest Float (`div`, `mul`,
/// `add`, `sub`, `inv`) or to nearest at 41 digits (`pow`), per SPEC.md.
contract LibDecimalFloatConsumerHazardsTest is Test {
    using LibDecimalFloat for Float;

    function mulExternal(Float a, Float b) external pure returns (Float) {
        return a.mul(b);
    }

    function addExternal(Float a, Float b) external pure returns (Float) {
        return a.add(b);
    }

    function divExternal(Float a, Float b) external pure returns (Float) {
        return a.div(b);
    }

    /// Subtracting any positive amount below one ulp of a positive Float takes
    /// a whole ulp off it: repaying 1 wei of a 1e76-wei debt clears 1e9 wei.
    function testSubBelowUlpStepsOneUlp() external pure {
        Float debt = LibDecimalFloat.packLossless(1e66, 10);
        Float repaid = LibDecimalFloat.packLossless(1, 0);
        assertTrue(debt.sub(repaid).eq(LibDecimalFloat.packLossless(1e67 - 1, 9)));
        Float d = debt;
        for (uint256 i = 0; i < 100; i++) {
            d = d.sub(repaid);
        }
        assertTrue(d.eq(LibDecimalFloat.packLossless(1e67 - 100, 9)));
    }

    /// A tiny add to a large Float is absorbed entirely.
    function testAddBelowUlpAbsorbed() external pure {
        Float bal = LibDecimalFloat.packLossless(1e66, 10);
        assertTrue(bal.add(LibDecimalFloat.packLossless(1, 0)).eq(bal));
    }

    /// A uint256 amount past 67 digits truncates on the way in.
    function testFromFixedAboveInt224Truncates() external pure {
        uint256 v = 1e70 + 123;
        (Float f, bool lossless) = LibDecimalFloat.fromFixedDecimalLossyPacked(v, 18);
        assertFalse(lossless);
        (uint256 back, bool backLossless) = f.toFixedDecimalLossy(18);
        assertEq(back, 1e70);
        assertTrue(backLossless);
    }

    /// Numerically equal Floats differ byte-wise until canonicalized.
    function testEqualValuesDifferentBytes() external pure {
        Float a = LibDecimalFloat.packLossless(1, 0);
        Float b = LibDecimalFloat.packLossless(10, -1);
        assertTrue(a.eq(b));
        assertTrue(Float.unwrap(a) != Float.unwrap(b));
        assertEq(Float.unwrap(a.canonicalize()), Float.unwrap(b.canonicalize()));
    }

    /// A caller-supplied extreme Float makes an ordinary `mul` or `add`
    /// revert.
    function testExtremeOperandReverts() external {
        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, int256(5), int256(type(int32).min) - 1));
        this.mulExternal(LibDecimalFloat.FLOAT_MIN_POSITIVE_VALUE, LibDecimalFloat.FLOAT_HALF);
        vm.expectRevert(
            abi.encodeWithSelector(
                ExponentOverflow.selector, int256(type(int224).max) * 2e9, int256(type(int32).max) - 9
            )
        );
        this.addExternal(LibDecimalFloat.FLOAT_MAX_POSITIVE_VALUE, LibDecimalFloat.FLOAT_MAX_POSITIVE_VALUE);
    }

    /// An empty market has nothing to divide by.
    function testEmptyMarketDivisionByZero() external {
        Float deposit = LibDecimalFloat.packLossless(1e18, 0);
        vm.expectRevert(abi.encodeWithSelector(DivisionByZero.selector, int256(1e18), int256(0)));
        this.divExternal(deposit, LibDecimalFloat.FLOAT_ZERO);
    }

    /// Empty-vault inflation: 1 share against 1e24 + 1 assets. A 1e18 deposit
    /// redeems all of it while shares stay Floats, and gets no shares once they
    /// are converted to an integer count.
    function testInflationAttackFloatVsFixedShares() external pure {
        Float totalShares = LibDecimalFloat.packLossless(1, 0);
        Float totalAssets = LibDecimalFloat.packLossless(1e24 + 1, 0);
        Float deposit = LibDecimalFloat.packLossless(1e18, 0);
        Float shares = deposit.mul(totalShares).div(totalAssets);
        assertTrue(
            shares.eq(
                LibDecimalFloat.packLossless(9999999999999999999999990000000000000000000000009999999999999999999, -73)
            )
        );
        Float redeem = shares.mul(totalAssets.add(deposit)).div(totalShares.add(shares));
        (uint256 redeemed, bool lossless) = redeem.toFixedDecimalLossy(0);
        assertEq(redeemed, 1e18);
        assertTrue(lossless);
        (uint256 intShares, bool sharesLossless) = shares.toFixedDecimalLossy(0);
        assertEq(intShares, 0);
        assertFalse(sharesLossless);
    }

    /// The Float keeps the fraction; the conversion back to wei drops it
    /// (8.900000000000000008 -> 8).
    function testTinyBalanceRelativeErrorOnlyAtBoundary() external pure {
        Float bal = LibDecimalFloat.packLossless(8, 0);
        Float rate = LibDecimalFloat.packLossless(1112500000000000001, -18);
        Float up = bal.mul(rate);
        assertTrue(up.eq(LibDecimalFloat.packLossless(8900000000000000008, -18)));
        (uint256 wei_, bool lossless) = up.toFixedDecimalLossy(0);
        assertEq(wei_, 8);
        assertFalse(lossless);
    }

    /// Converting to wei on every step of a loop amplifies: each round trip
    /// through the rate loses a wei of 8 and empties the balance in eight
    /// steps, where the Float balance stays exactly 8.
    function testWeiPerStepLoopAmplifies() external pure {
        Float rate = LibDecimalFloat.packLossless(1112500000000000001, -18);
        Float floatBal = LibDecimalFloat.packLossless(8, 0);
        uint256 weiBal = 8;
        for (uint256 i = 0; i < 8; i++) {
            floatBal = floatBal.mul(rate).div(rate);
            (uint256 up,) = LibDecimalFloat.fromFixedDecimalLosslessPacked(weiBal, 0).mul(rate).toFixedDecimalLossy(0);
            (weiBal,) = LibDecimalFloat.fromFixedDecimalLosslessPacked(up, 0).div(rate).toFixedDecimalLossy(0);
            assertEq(weiBal, 7 - i);
        }
        assertTrue(floatBal.eq(LibDecimalFloat.packLossless(8, 0)));
    }

    /// A toward-zero result used as a divisor biases away from zero: 1/6
    /// truncates to 67 sixes, and inverting that lands above 6.
    function testInvInvAboveExact() external pure {
        Float six = LibDecimalFloat.packLossless(6, 0);
        Float sixth = six.inv();
        assertTrue(
            sixth.eq(
                LibDecimalFloat.packLossless(1666666666666666666666666666666666666666666666666666666666666666666, -67)
            )
        );
        Float back = sixth.inv();
        assertTrue(
            back.eq(
                LibDecimalFloat.packLossless(6000000000000000000000000000000000000000000000000000000000000000002, -66)
            )
        );
        assertTrue(back.gt(six));
        for (int256 n = 2; n < 6; n++) {
            Float f = LibDecimalFloat.packLossless(n, 0);
            assertTrue(f.inv().inv().eq(f));
        }
    }

    /// Toward zero is toward +infinity for a negative result.
    function testNegativeRoundsUp() external pure {
        Float third = LibDecimalFloat.packLossless(-1, 0).div(LibDecimalFloat.packLossless(3, 0));
        assertTrue(
            third.eq(
                LibDecimalFloat.packLossless(-3333333333333333333333333333333333333333333333333333333333333333333, -67)
            )
        );
    }

    /// Integer inputs with a*b at most 1e66: the floor of the Float result of
    /// a*b/c never exceeds mulDiv floor and the lossless-flag ceiling never
    /// falls below mulDiv ceiling, whichever of three operand orders computes
    /// it. Each misses by at most 1, and only when a*b/c is an exact integer.
    function testFuzzWeiFloorCeilSafeSide(uint256 a, uint256 b, uint256 c) external pure {
        a = bound(a, 0, 1e33);
        b = bound(b, 1, 1e33);
        c = bound(c, 1, 1e33);
        Float fa = LibDecimalFloat.fromFixedDecimalLosslessPacked(a, 0);
        Float fb = LibDecimalFloat.fromFixedDecimalLosslessPacked(b, 0);
        Float fc = LibDecimalFloat.fromFixedDecimalLosslessPacked(c, 0);
        uint256 floorExact = a * b / c;
        bool exactInt = a * b % c == 0;
        uint256 ceilExact = floorExact + (exactInt ? 0 : 1);

        Float[3] memory results = [fa.mul(fb).div(fc), fa.div(fc.div(fb)), fa.mul(fb.div(fc))];
        for (uint256 i = 0; i < 3; i++) {
            (uint256 got, bool lossless) = results[i].toFixedDecimalLossy(0);
            uint256 ceilGot = got + (lossless ? 0 : 1);
            if (!exactInt) {
                assertEq(got, floorExact);
                assertEq(ceilGot, ceilExact);
            } else {
                assertLe(got, floorExact);
                assertGe(ceilGot, ceilExact);
                assertGe(got + 1, floorExact);
                assertLe(ceilGot, ceilExact + 1);
            }
        }
    }

    /// Dividing by a truncated price turns an exact integer into a lossy
    /// result: the lossless-flag ceiling charges 1 more than mulDivUp.
    function testExactIntegerCeilOvercharge() external pure {
        uint256 a = 1934;
        uint256 b = 82730218427561513643844186791816;
        Float fa = LibDecimalFloat.fromFixedDecimalLosslessPacked(a, 0);
        Float fb = LibDecimalFloat.fromFixedDecimalLosslessPacked(b, 0);
        (uint256 got, bool lossless) = fa.div(LibDecimalFloat.FLOAT_TWO.div(fb)).toFixedDecimalLossy(0);
        assertEq(a * b % 2, 0);
        assertEq(got, a * b / 2);
        assertFalse(lossless);
    }

    /// Past about 1e66 the floor lands on the unsafe side: (7e66 + 2) * 3 / 7
    /// is 3e66 + 6/7, and a / (7 / 3) floors to 3e66 + 1.
    function testLargeMagnitudeFloorOvershoots() external pure {
        uint256 a = 7e66 + 2;
        Float fa = LibDecimalFloat.fromFixedDecimalLosslessPacked(a, 0);
        Float seven = LibDecimalFloat.packLossless(7, 0);
        Float three = LibDecimalFloat.packLossless(3, 0);
        (uint256 got,) = fa.div(seven.div(three)).toFixedDecimalLossy(0);
        assertEq(a * 3 / 7, 3e66);
        assertEq(got, 3e66 + 1);
    }

    /// pow(a, 1) rounds to 41 significant digits, to nearest, half away from
    /// zero: a 42-digit `a` ending in 5 comes back above `a`.
    function testPowOneRoundsUp() external pure {
        Float a = LibDecimalFloat.packLossless(123456789012345678901234567890123456789015, -41);
        Float p = a.pow(LibDecimalFloat.FLOAT_ONE);
        assertTrue(p.eq(LibDecimalFloat.packLossless(12345678901234567890123456789012345678902, -40)));
        assertTrue(p.gt(a));
    }

    /// `pow(r, w) - 1` for r within 1e-41 of 1 is zero: the 41-digit result
    /// cannot see the ratio.
    function testPowMinusOneChargeIsZero() external pure {
        Float r = LibDecimalFloat.packLossless(1e45 + 4, -45);
        assertTrue(r.pow(LibDecimalFloat.packLossless(5, -1)).eq(LibDecimalFloat.FLOAT_ONE));
        assertTrue(r.pow(LibDecimalFloat.packLossless(7, -1)).eq(LibDecimalFloat.FLOAT_ONE));
    }
}
