// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "../../../src/lib/LibDecimalFloat.sol";
import {ExponentUnderflow, ExponentOverflow, DivisionByZero} from "../../../src/error/ErrDecimalFloat.sol";

// Bound on a*b under which testFuzzWeiFloorCeilSafeSide holds in every operand
// order: 20ab <= int224.max.
uint256 constant WEI_SAFE_SIDE_AB_MAX = uint256(int256(type(int224).max)) / 20;

/// Tests behind the README's consumer guidance. Expected values are the exact
/// result rounded toward zero to the nearest Float (`div`, `mul`, `add`, `sub`,
/// `inv`) or to nearest at 41 digits (`pow`), per SPEC.md.
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

    /// README precision example: 1/3 keeps 67 threes, 1/9 keeps 68 ones
    /// because 1.1e67 fits int224 where 3.3e67 does not, and so
    /// (1/3) / (1/9) is exactly 3 (10^68 - 10) / (10^68 - 1) < 3, which
    /// truncates to 2.(66 nines). (1/9) / (1/3) is exactly 0.(67 threes).
    function testReadmeThirdsAndNinths() external pure {
        Float one = LibDecimalFloat.FLOAT_ONE;
        Float three = LibDecimalFloat.packLossless(3, 0);
        Float third = one.div(three);
        Float ninth = one.div(LibDecimalFloat.packLossless(9, 0));
        assertEq(
            Float.unwrap(third),
            Float.unwrap(
                LibDecimalFloat.packLossless(3333333333333333333333333333333333333333333333333333333333333333333, -67)
            )
        );
        assertEq(
            Float.unwrap(ninth),
            Float.unwrap(
                LibDecimalFloat.packLossless(11111111111111111111111111111111111111111111111111111111111111111111, -68)
            )
        );
        assertEq(Float.unwrap(ninth.div(third)), Float.unwrap(third));
        Float thirdOverNinth = third.div(ninth);
        assertEq(
            Float.unwrap(thirdOverNinth),
            Float.unwrap(
                LibDecimalFloat.packLossless(2999999999999999999999999999999999999999999999999999999999999999999, -66)
            )
        );
        assertTrue(thirdOverNinth.lt(three));
    }

    /// The domain of testFuzzWeiFloorCeilSafeSide: a in [0, 1e33], b and c in
    /// [1, 1e33], and a * b at most WEI_SAFE_SIDE_AB_MAX.
    function boundWeiSafeSide(uint256 a, uint256 b, uint256 c) internal pure returns (uint256, uint256, uint256) {
        a = bound(a, 0, 1e33);
        b = bound(b, 1, 1e33);
        if (a > 0) {
            b = bound(b, 1, WEI_SAFE_SIDE_AB_MAX / a);
        }
        c = bound(c, 1, 1e33);
        return (a, b, c);
    }

    /// Integer inputs with a*b at most int224.max / 20: the floor of the Float
    /// result of a*b/c never exceeds mulDiv floor and the lossless-flag ceiling
    /// never falls below mulDiv ceiling, whichever of three operand orders
    /// computes it. Each misses by at most 1, and only when a*b/c is an exact
    /// integer.
    ///
    /// Each operation truncates toward zero to a Float, moving its result by
    /// under 10 / int224.max of it. With q = a*b/c, a non-integer q is at least
    /// 1/c from both neighbouring integers. a * (b / c) truncates twice, each
    /// step taking under (1/c)(10ab / int224.max) off q, and a / (c / b) adds at
    /// most about as much through the truncated divisor. While 20ab <= int224.max
    /// either total stays under 1/c, so the result keeps a fraction, its floor is
    /// exact and the lossless flag stays false.
    function testFuzzWeiFloorCeilSafeSide(uint256 a, uint256 b, uint256 c) external pure {
        (a, b, c) = boundWeiSafeSide(a, b, c);
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

    /// The pinned inputs above WEI_SAFE_SIDE_AB_MAX where a * (b / c) reports an
    /// exact integer for a non-integer a*b/c, with a*b at about 0.0732, 0.0701,
    /// 0.0630 and 0.0510 of int224.max.
    function weiCeilUndershootInputs() internal pure returns (uint256[3][4] memory) {
        return [
            [uint256(987095638915421968423246895997630), 999999999999999999999999999999999, 7],
            [uint256(982988587715706933722833015409834), 961104254074084716688159570998290, 7],
            [uint256(991490827453364970410514390968066), 857267960192621109581636881564001, 63],
            [uint256(999999999999999999999999999999959), 687478640012341314764008884719033, 51]
        ];
    }

    /// a * (b / c) is exactly floor(a*b/c) and the conversion reports lossless
    /// although c does not divide a*b, so the lossless-flag ceiling is one below
    /// the exact ceiling. Only inputs above WEI_SAFE_SIDE_AB_MAX can do this.
    function assertCeilUndershoot(uint256 a, uint256 b, uint256 c) internal pure {
        assertGt(a * b, WEI_SAFE_SIDE_AB_MAX);
        assertTrue(a * b % c != 0);
        Float fa = LibDecimalFloat.fromFixedDecimalLosslessPacked(a, 0);
        Float fb = LibDecimalFloat.fromFixedDecimalLosslessPacked(b, 0);
        Float fc = LibDecimalFloat.fromFixedDecimalLosslessPacked(c, 0);
        (uint256 got, bool lossless) = fa.mul(fb.div(fc)).toFixedDecimalLossy(0);
        assertEq(got, a * b / c);
        assertTrue(lossless);
    }

    /// Above int224.max / 20 the lossless-flag ceiling can fall below the exact
    /// ceiling. a*b is about 0.073 int224.max and a*b/c is
    /// 141013662702203138346178127999661287557765869225433082393300571767 + 1/7.
    /// b/c truncates to 67 digits and a times it loses about 0.085; the product
    /// has 66 integer digits, so packing keeps one decimal and drops the rest of
    /// the fraction. The Float is an integer, the flag reports lossless, and the
    /// ceiling is the floor.
    function testWeiCeilUndershootAboveBound() external pure {
        uint256[3] memory input = weiCeilUndershootInputs()[0];
        (uint256 a, uint256 b, uint256 c) = (input[0], input[1], input[2]);
        assertCeilUndershoot(a, b, c);
        assertEq(a * b % c, 1);
        assertEq(a * b / c, 141013662702203138346178127999661287557765869225433082393300571767);
    }

    /// A failing a*b of about 0.0701 int224.max, inside the 1e33 operand bounds:
    /// a * (b / c) reports an exact integer for a non-integer a*b/c. The assertGt
    /// in assertCeilUndershoot pins WEI_SAFE_SIDE_AB_MAX below it.
    function testWeiCeilUndershootJustAboveBound() external pure {
        uint256[3] memory input = weiCeilUndershootInputs()[1];
        (uint256 a, uint256 b, uint256 c) = (input[0], input[1], input[2]);
        assertCeilUndershoot(a, b, c);
        assertLe(a, 1e33);
        assertLe(b, 1e33);
        assertEq(a * b % c, 1);
        assertEq(a * b / c, 134964930479977501092417587112111680069047645347077958594980454837);
    }

    /// a*b about 0.0630 int224.max, inside int224.max / 15: a * (b / c) reports
    /// an exact integer for a non-integer a*b/c.
    function testWeiCeilUndershootInsideFifteenth() external pure {
        uint256[3] memory input = weiCeilUndershootInputs()[2];
        (uint256 a, uint256 b, uint256 c) = (input[0], input[1], input[2]);
        assertCeilUndershoot(a, b, c);
        assertLe(a * b, uint256(int256(type(int224).max)) / 15);
        assertEq(a * b / c, 13491639987311749946720071013608698805283216399205952474008352255);
    }

    /// The bound is tight: a*b about 0.0510 int224.max, inside int224.max / 19,
    /// fails the same way. Both truncations of a * (b / c) are as coarse as
    /// they can be. b / c packs with a coefficient just above int224.max / 10 at
    /// exponent -35, so a times its dropped tail is under 0.01 and here 0.0098;
    /// the product has 65 integer digits and packs at exponent -2, dropping
    /// under 0.01 more. Together they can cover a fraction up to 0.02, and
    /// a*b/c has fraction 1/51. The same construction with c = 5 * 10^(k-2) + 1
    /// fails at about (1/20 + 10^-k) int224.max.
    function testWeiCeilUndershootNearBound() external pure {
        uint256[3] memory input = weiCeilUndershootInputs()[3];
        (uint256 a, uint256 b, uint256 c) = (input[0], input[1], input[2]);
        assertCeilUndershoot(a, b, c);
        assertLe(a * b, uint256(int256(type(int224).max)) / 19);
        assertEq(a * b % c, 1);
        assertEq(a * b / c, 13479973333575319897333507543509898301485480274629307365406402346);
    }

    /// One mul can drop a sub-ulp fraction: 2e18 * (1 + 1e-67) is
    /// 2e18 + 2e-49, the Float is exactly 2e18 and the conversion reports
    /// lossless, so the lossless-flag ceiling is 1 below the exact ceiling.
    function testSingleMulSubUlpFractionReadsLossless() external pure {
        Float amount = LibDecimalFloat.fromFixedDecimalLosslessPacked(2e18, 0);
        Float rate = LibDecimalFloat.packLossless(1e67 + 1, -67);
        (int256 rateCoefficient, int256 rateExponent) = rate.unpack();
        assertEq(rateExponent, -67);
        assertEq(rateCoefficient % 1e67, 1);
        (uint256 got, bool lossless) = amount.mul(rate).toFixedDecimalLossy(0);
        assertEq(got, 2e18);
        assertTrue(lossless);
    }

    /// One div can do the same: (1e67 + 3) / 7 has remainder 6, but the
    /// quotient's 67 integer digits fill the coefficient, so the Float is the
    /// floor and the conversion reports lossless.
    function testSingleDivSubUlpFractionReadsLossless() external pure {
        uint256 a = 1e67 + 3;
        Float fa = LibDecimalFloat.fromFixedDecimalLosslessPacked(a, 0);
        (uint256 got, bool lossless) = fa.div(LibDecimalFloat.packLossless(7, 0)).toFixedDecimalLossy(0);
        assertEq(a % 7, 6);
        assertEq(got, a / 7);
        assertTrue(lossless);
    }

    /// A later mul scales an earlier truncation: one ulp of each intermediate is
    /// not enough margin. 94e66 * (1 / 7) loses about 4.43, so the ulp margin of
    /// about 1 falls 4 short of the exact ceiling.
    function testMarginScalesThroughLaterMul() external pure {
        Float a = LibDecimalFloat.packLossless(94, 66);
        Float seventh = LibDecimalFloat.packLossless(1, 0).div(LibDecimalFloat.packLossless(7, 0));
        Float res = a.mul(seventh);
        uint256 exactCeil = (uint256(94e66) + 6) / 7;
        (, int256 seventhExponent) = seventh.unpack();
        (, int256 resExponent) = res.unpack();
        Float ulpMargin =
            LibDecimalFloat.packLossless(1, seventhExponent).add(LibDecimalFloat.packLossless(1, resExponent));
        (uint256 got, bool lossless) = res.add(ulpMargin).toFixedDecimalLossy(0);
        assertEq(got + (lossless ? 0 : 1), exactCeil - 4);
    }

    /// The margin is per operation: a * (1 / 73) here loses about 1.45e-66 of
    /// the result over its two truncations, so 1e-66 of the result leaves the
    /// lossless-flag ceiling 10 short. 2e-66 reaches it on this input, which
    /// says nothing about other inputs: testMarginCountsItsOwnAdd has one where
    /// it falls short.
    function testMarginIsPerOperation() external pure {
        uint256 aCoefficient = 9925887261852452467399719857351126276300750130317078586257692491778;
        Float a = LibDecimalFloat.fromFixedDecimalLosslessPacked(aCoefficient * 100, 0);
        Float res = a.mul(LibDecimalFloat.packLossless(1, 0).div(LibDecimalFloat.packLossless(73, 0)));
        uint256 exactCeil = (aCoefficient * 100 + 72) / 73;
        (uint256 got, bool lossless) = res.add(res.mul(LibDecimalFloat.packLossless(1, -66))).toFixedDecimalLossy(0);
        assertEq(got + (lossless ? 0 : 1), exactCeil - 10);
        (got, lossless) = res.add(res.mul(LibDecimalFloat.packLossless(2, -66))).toFixedDecimalLossy(0);
        assertEq(got + (lossless ? 0 : 1), exactCeil);
    }

    /// The add that applies the margin truncates to the result's grid too, so
    /// it costs up to one ulp of the result on top of the ops. Two ops with a
    /// 2e-66 margin leave the lossless-flag ceiling 1 short here; 3e-66, one
    /// per op plus one for the add, reaches the exact ceiling.
    function testMarginCountsItsOwnAdd() external pure {
        uint256 aFixed = 10807643726145906666284575962433451640027389170232479141916483202116 * 1000;
        Float a = LibDecimalFloat.fromFixedDecimalLosslessPacked(aFixed, 0);
        Float res = a.mul(LibDecimalFloat.packLossless(1, 0).div(LibDecimalFloat.packLossless(7345, 0)));
        uint256 exactCeil = (aFixed + 7344) / 7345;
        assertEq(aFixed % 7345, 170);
        (uint256 got, bool lossless) = res.add(res.mul(LibDecimalFloat.packLossless(2, -66))).toFixedDecimalLossy(0);
        assertEq(got + (lossless ? 0 : 1), exactCeil - 1);
        (got, lossless) = res.add(res.mul(LibDecimalFloat.packLossless(3, -66))).toFixedDecimalLossy(0);
        assertEq(got + (lossless ? 0 : 1), exactCeil + 1);
    }

    /// add truncates too. 13479e63 + 9 plus 2e63 + 9 is 13481e63 + 18, which
    /// exceeds int224.max and packs to 13481e63 + 10; adding 9 packs to the
    /// same Float. The exact sum is 13481e63 + 27. A margin counting no add,
    /// 1e-66 of the result for the add that applies it, leaves the
    /// lossless-flag ceiling 7 short; 3e-66, one per add plus one for the
    /// margin's add, reaches it.
    function testMarginCountsAdds() external pure {
        uint256 firstAddend = 13479e63 + 9;
        uint256 secondAddend = 2e63 + 9;
        uint256 thirdAddend = 9;
        Float res = LibDecimalFloat.fromFixedDecimalLosslessPacked(firstAddend, 0)
            .add(LibDecimalFloat.fromFixedDecimalLosslessPacked(secondAddend, 0))
            .add(LibDecimalFloat.fromFixedDecimalLosslessPacked(thirdAddend, 0));
        uint256 exactSum = firstAddend + secondAddend + thirdAddend;
        (uint256 got, bool lossless) = res.toFixedDecimalLossy(0);
        assertEq(got, exactSum - 17);
        assertTrue(lossless);
        (got, lossless) = res.add(res.mul(LibDecimalFloat.packLossless(1, -66))).toFixedDecimalLossy(0);
        assertEq(got + (lossless ? 0 : 1), exactSum - 7);
        (got, lossless) = res.add(res.mul(LibDecimalFloat.packLossless(3, -66))).toFixedDecimalLossy(0);
        assertEq(got + (lossless ? 0 : 1), exactSum + 23);
    }

    /// A cancelling sub amplifies an earlier loss relative to the result. 94e66
    /// times the Float 1 / 7 is floor(94e66 / 7) - 4, about 4.43 under the
    /// exact product of 1.34e67. Subtracting floor(94e66 / 7) - 1000 leaves 996
    /// where the exact value is 1000 + 3/7, so the exact ceiling is 1001. A
    /// 3e-66 margin relative to 996 is a sub-wei fraction the conversion
    /// flags, so it lifts the ceiling by one wei, 4 short. Margining the
    /// product on its safe side first, 2e-66 for its mul and the add, reaches
    /// the ceiling.
    function testMarginRelativeToResultFailsUnderCancellation() external pure {
        Float a = LibDecimalFloat.packLossless(94, 66);
        Float seven = LibDecimalFloat.packLossless(7, 0);
        Float product = a.mul(LibDecimalFloat.packLossless(1, 0).div(seven));
        (uint256 got, bool lossless) = product.toFixedDecimalLossy(0);
        assertEq(got, uint256(94e66) / 7 - 4);
        assertTrue(lossless);
        Float quotient = a.div(seven);
        (got, lossless) = quotient.toFixedDecimalLossy(0);
        assertEq(got, uint256(94e66) / 7);
        assertTrue(lossless);
        Float subtrahend = quotient.sub(LibDecimalFloat.packLossless(1000, 0));
        uint256 exactCeil = 1000 + (uint256(94e66) % 7 + 6) / 7;
        assertEq(exactCeil, 1001);
        Float res = product.sub(subtrahend);
        assertTrue(res.eq(LibDecimalFloat.packLossless(996, 0)));
        (got, lossless) = res.add(res.mul(LibDecimalFloat.packLossless(3, -66))).toFixedDecimalLossy(0);
        assertEq(got, 996);
        assertFalse(lossless);
        assertEq(got + (lossless ? 0 : 1), exactCeil - 4);
        (got, lossless) =
            product.add(product.mul(LibDecimalFloat.packLossless(2, -66))).sub(subtrahend).toFixedDecimalLossy(0);
        assertEq(got + (lossless ? 0 : 1), exactCeil + 21);
    }

    /// README rule 1's margin on a positive chain: n operations drawn from mul,
    /// div and add on an integer in [1e66, 1e67] and integer operands in
    /// [1, 1e3], then
    /// a margin of (n + 1)e-66 of the result, give a lossless-flag ceiling at
    /// least the exact ceiling and at most floor((n + 1)e-66 × exact) + 1 above
    /// it. Every operand is exact and each op truncates by under
    /// 10 / int224.max of its result, which holds while every intermediate is
    /// at least 1e-2147483581 so that the exponent floor never cuts a
    /// coefficient short (here every intermediate is at least 1e66 / 1e9 and the
    /// margin at least 4e-9; testMarginFailsAtExponentFloor is the rule failing
    /// below it), so the computed value is at least the exact value times
    /// (1 - 7.42e-67)^n; the mul that sizes the margin truncates the margin by
    /// under that fraction of itself, the add that applies it truncates once
    /// more, and (1 - 7.42e-67)^(n + 1) (1 + (n + 1)e-66 (1 - 7.42e-67))
    /// exceeds 1. The margin only adds, so the result is at most
    /// exact (1 + (n + 1)e-66), whose ceiling is at most
    /// ceil(exact) + floor((n + 1)e-66 × exact) + 1. The first operand sits on
    /// the wei grid of a 68-digit Float, so on chains whose result stays near
    /// 1e67 or above (mul and add) each loss and the margin reach whole wei:
    /// there no margin, 1e-66 once, or an order more each fail. Chains through
    /// div shrink the result and only check that the margin suffices. The
    /// numerator stays under 1e67 × 1e9 = 1e76.
    function testFuzzMarginPerOperationPositiveChain(uint256[4] memory operands, uint8 ops) external pure {
        uint256 opCount = operands.length - 1;
        operands[0] = bound(operands[0], 1e66, 1e67);
        for (uint256 i = 1; i <= opCount; i++) {
            operands[i] = bound(operands[i], 1, 1e3);
        }
        Float acc = LibDecimalFloat.fromFixedDecimalLosslessPacked(operands[0], 0);
        uint256 numerator = operands[0];
        uint256 denominator = 1;
        for (uint256 i = 1; i <= opCount; i++) {
            Float operand = LibDecimalFloat.fromFixedDecimalLosslessPacked(operands[i], 0);
            uint256 op = (ops >> (2 * (i - 1))) % 3;
            if (op == 0) {
                acc = acc.mul(operand);
                numerator *= operands[i];
            } else if (op == 1) {
                acc = acc.div(operand);
                denominator *= operands[i];
            } else {
                acc = acc.add(operand);
                numerator += operands[i] * denominator;
            }
        }
        uint256 exactCeil = (numerator + denominator - 1) / denominator;
        uint256 marginFloor = numerator * (opCount + 1) / 1e66 / denominator;
        Float margin = acc.mul(LibDecimalFloat.fromFixedDecimalLosslessPacked(opCount + 1, 66));
        (uint256 got, bool lossless) = acc.add(margin).toFixedDecimalLossy(0);
        uint256 ceilGot = got + (lossless ? 0 : 1);
        assertGe(ceilGot, exactCeil);
        assertLe(ceilGot, exactCeil + marginFloor + 1);
    }

    /// README rule 1 with inv in the chain: a × inv(d), two ops, with a 3e-66
    /// margin of the result gives a lossless-flag ceiling at least the exact
    /// ceiling of a / d and at most floor(3e-66 × a / d) above it: by the proof
    /// of testFuzzMarginPerOperationPositiveChain at n = 2 it is above a / d and
    /// at most a / d + 3e-66 × a / d, and as a Float of at least 1e67 it is an
    /// integer (testMarginInvChainUpperBoundAttained reaches it). inv has its
    /// own path in the library, so this checks rule 1's margin through that
    /// path as well as through div. a is an integer in [1e66, 1e67] times 1e4
    /// and d is in [2, 1e3], so a / d is at least 1e67 and every loss and the
    /// margin are whole wei: no margin, 1e-66 once, or an order more each fail,
    /// and 2e-66 fails on the input testMarginInvCountsItsOwnAdd pins.
    function testFuzzMarginInvChain(uint256 numerator, uint256 divisor) external pure {
        numerator = bound(numerator, 1e66, 1e67) * 1e4;
        divisor = bound(divisor, 2, 1e3);
        Float acc = LibDecimalFloat.fromFixedDecimalLosslessPacked(numerator, 0)
            .mul(LibDecimalFloat.fromFixedDecimalLosslessPacked(divisor, 0).inv());
        uint256 exactCeil = (numerator + divisor - 1) / divisor;
        uint256 marginFloor = numerator * 3 / 1e66 / divisor;
        Float margin = acc.mul(LibDecimalFloat.fromFixedDecimalLosslessPacked(3, 66));
        (uint256 got, bool lossless) = acc.add(margin).toFixedDecimalLossy(0);
        uint256 ceilGot = got + (lossless ? 0 : 1);
        assertGe(ceilGot, exactCeil);
        assertLe(ceilGot, exactCeil + marginFloor);
    }

    /// testFuzzMarginInvChain's upper bound is attained: 1e70 × inv(1000) is
    /// exactly 1e67, its 3e-66 margin is exactly 30, and the sum fits a
    /// coefficient at exponent 0, so the lossless-flag ceiling is exactly
    /// floor(3e-66 × a / d) above the exact ceiling.
    function testMarginInvChainUpperBoundAttained() external view {
        Float acc = LibDecimalFloat.fromFixedDecimalLosslessPacked(1e70, 0)
            .mul(LibDecimalFloat.fromFixedDecimalLosslessPacked(1000, 0).inv());
        assertTrue(acc.eq(LibDecimalFloat.packLossless(1e67, 0)));
        assertTrue(
            acc.add(acc.mul(LibDecimalFloat.packLossless(3, -66))).eq(LibDecimalFloat.packLossless(1e67 + 30, 0))
        );
        this.testFuzzMarginInvChain(1e66, 1000);
    }

    /// The margin's own add on the inv path: a × inv(730) packs to a multiple
    /// of 10 about 20.55 below a / 730. A 2e-66 margin, about 29.36, puts the
    /// sum about 8.81 above a / 730, and the add truncates it to
    /// floor(a / 730), a multiple of 10, so the lossless-flag ceiling is 1
    /// short. 3e-66, one per op plus one for the add, reaches it. The same
    /// input fails testFuzzMarginInvChain under a 2e-66 margin.
    function testMarginInvCountsItsOwnAdd() external view {
        uint256 numerator = 1071481643597238231781514733015558570712902379074599554133101278361;
        uint256 divisor = 730;
        uint256 aFixed = numerator * 1e4;
        Float res = LibDecimalFloat.fromFixedDecimalLosslessPacked(aFixed, 0)
            .mul(LibDecimalFloat.fromFixedDecimalLosslessPacked(divisor, 0).inv());
        uint256 exactCeil = (aFixed + divisor - 1) / divisor;
        assertEq(aFixed % divisor, 400);
        assertEq(aFixed / divisor % 10, 0);
        (uint256 got, bool lossless) = res.add(res.mul(LibDecimalFloat.packLossless(2, -66))).toFixedDecimalLossy(0);
        assertEq(got + (lossless ? 0 : 1), exactCeil - 1);
        (got, lossless) = res.add(res.mul(LibDecimalFloat.packLossless(3, -66))).toFixedDecimalLossy(0);
        assertEq(got + (lossless ? 0 : 1), exactCeil + 19);
        this.testFuzzMarginInvChain(numerator, divisor);
    }

    /// The margin rule's hypothesis fails at the exponent floor: a result below
    /// about 1.35e-2147483582 cannot keep a coefficient above int224.max / 10,
    /// so one op can lose far more than 1e-66 of it. 3e-2147483648 / 2 packs to
    /// 1e-2147483648, a third lost; times 1e13 × 10^int32.max that is 1e12
    /// where the exact product is 1.5e12, and rule 1's 3e-66 margin for the two
    /// ops and its own add leaves the lossless-flag ceiling at 1e12 + 1, 5e11 - 1
    /// below the exact ceiling.
    function testMarginFailsAtExponentFloor() external pure {
        Float quotient = LibDecimalFloat.packLossless(3, type(int32).min).div(LibDecimalFloat.packLossless(2, 0));
        (int256 quotientCoefficient, int256 quotientExponent) = quotient.unpack();
        assertEq(quotientCoefficient, 1);
        assertEq(quotientExponent, type(int32).min);
        Float res = quotient.mul(LibDecimalFloat.packLossless(1e13, type(int32).max));
        assertTrue(res.eq(LibDecimalFloat.packLossless(1e12, 0)));
        Float margined = res.add(res.mul(LibDecimalFloat.packLossless(3, -66)));
        assertTrue(margined.eq(LibDecimalFloat.packLossless(1e66 + 3, -54)));
        uint256 exactCeil = 15e11;
        (uint256 got, bool lossless) = margined.toFixedDecimalLossy(0);
        assertEq(got, 1e12);
        assertFalse(lossless);
        assertEq(exactCeil - (got + 1), 5e11 - 1);
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

    /// Far above WEI_SAFE_SIDE_AB_MAX a rounded divisor lifts the floor onto the
    /// unsafe side: (7e66 + 2) * 3 / 7 is 3e66 + 6/7, and a / (7 / 3) floors to
    /// 3e66 + 1.
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

    /// The fuzz domain excludes the known counterexamples above the bound, and
    /// the call site keeps the clamp on b: each triple fed as (a, c, b) lies
    /// inside the domain, and reaches the counterexample only if b and c trade
    /// places after bounding.
    function testFuzzWeiFloorCeilSafeSideBoundsCounterexample() external view {
        uint256[3][4] memory inputs = weiCeilUndershootInputs();
        for (uint256 i = 0; i < inputs.length; i++) {
            this.testFuzzWeiFloorCeilSafeSide(inputs[i][0], inputs[i][1], inputs[i][2]);
            this.testFuzzWeiFloorCeilSafeSide(inputs[i][0], inputs[i][2], inputs[i][1]);
        }
    }

    /// The clamp limit is WEI_SAFE_SIDE_AB_MAX / a: at the smallest a where it
    /// is below 1e33 it admits a*b up to WEI_SAFE_SIDE_AB_MAX and wraps the
    /// input just above it onto b = 1, never b = 0, so a guard that skips the
    /// clamp at that a fails. Each operand wraps at 1e33.
    function testWeiSafeSideDomainInteriorEdges() external pure {
        uint256 a = 673998666678765994866675377175491;
        uint256 edge = WEI_SAFE_SIDE_AB_MAX / a;
        assertLt(edge, 1e33);
        assertGe(WEI_SAFE_SIDE_AB_MAX / (a - 1), 1e33);
        (, uint256 b,) = boundWeiSafeSide(a, edge, 7);
        assertEq(b, edge);
        (, b,) = boundWeiSafeSide(a, edge + 1, 7);
        assertEq(b, 1);
        (, b,) = boundWeiSafeSide(1, 1e33, 7);
        assertEq(b, 1e33);
        (, b,) = boundWeiSafeSide(1, 1e33 + 1, 7);
        assertEq(b, 1);
        (uint256 aOut,, uint256 cOut) = boundWeiSafeSide(1e33 + 1, 1, 1e33 + 1);
        assertEq(aOut, 0);
        assertEq(cOut, 1);
        (aOut,, cOut) = boundWeiSafeSide(1e33, 1, 1e33);
        assertEq(aOut, 1e33);
        assertEq(cOut, 1e33);
    }

    /// The domain reaches the bound: at a = 1e33 the clamp admits
    /// b = 673998666678765994866675377175490, the largest b with
    /// a * b <= WEI_SAFE_SIDE_AB_MAX, and the property holds there. The literal
    /// pins the constant from below as the pinned counterexamples pin it from
    /// above: a divisor other than 20 fails one of the first two assertions.
    function testWeiSafeSideDomainReachesBound() external view {
        uint256 a = 1e33;
        uint256 b = 673998666678765994866675377175490;
        assertLe(a * b, WEI_SAFE_SIDE_AB_MAX);
        assertGt(a * (b + 1), WEI_SAFE_SIDE_AB_MAX);
        (, uint256 bOut,) = boundWeiSafeSide(a, b, 7);
        assertEq(bOut, b);
        assertEq(a * b % 7, 5);
        this.testFuzzWeiFloorCeilSafeSide(a, b, 7);
    }

    /// a = 0 is in the domain and skips the clamp; b and c floor at 1, so no
    /// operand order divides by zero.
    function testWeiSafeSideZeroFloors() external pure {
        (uint256 a, uint256 b, uint256 c) = boundWeiSafeSide(0, 0, 0);
        assertEq(a, 0);
        assertEq(b, 1);
        assertEq(c, 1);
    }
}
