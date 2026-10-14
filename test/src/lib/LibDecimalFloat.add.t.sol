// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float, ExponentOverflow} from "src/lib/LibDecimalFloat.sol";
import {LibExactFloat} from "test/lib/LibExactFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {Test} from "forge-std-1.17.0/src/Test.sol";

contract LibDecimalFloatDecimalAddTest is Test {
    using LibDecimalFloat for Float;

    function addExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (Float)
    {
        (int256 signedCoefficientC, int256 exponentC) =
            LibDecimalFloatImplementation.add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        Float c = LibDecimalFloat.packArithmeticResult(signedCoefficientC, exponentC);
        return c;
    }

    function addExternal(Float a, Float b) external pure returns (Float) {
        return LibDecimalFloat.add(a, b);
    }

    /// The documented rounding of the exact sum (#350).
    function checkAddValue(Float a, Float b, Float result) internal pure {
        (int256 signedCoefficientA, int256 exponentA) = LibDecimalFloat.unpack(a);
        (int256 signedCoefficientB, int256 exponentB) = LibDecimalFloat.unpack(b);
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.unpack(result);
        assertTrue(
            LibExactFloat.isSumResult(
                signedCoefficientA, exponentA, signedCoefficientB, exponentB, signedCoefficient, exponent
            ),
            "documented rounding of the exact sum"
        );
    }

    /// Reverts only where the exact sum is beyond the largest Float of its
    /// sign, otherwise is the documented rounding of the exact sum (#350),
    /// and agrees with the unpacked path.
    function testAddPacked(Float a, Float b) external {
        (int256 signedCoefficientA, int256 exponentA) = LibDecimalFloat.unpack(a);
        (int256 signedCoefficientB, int256 exponentB) = LibDecimalFloat.unpack(b);
        if (LibExactFloat.addOverflows(signedCoefficientA, exponentA, signedCoefficientB, exponentB)) {
            (bool overflowed, int256 signedCoefficientSum, int256 exponentSum) =
                LibExactFloat.addPartsWide(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
            assertFalse(overflowed, "sum past int256 exponent");
            vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficientSum, exponentSum));
            this.addExternal(a, b);
            return;
        }
        Float resultParts = this.addExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.unpack(resultParts);
        Float result = this.addExternal(a, b);
        checkAddValue(a, b, result);
        (int256 signedCoefficientUnpacked, int256 exponentUnpacked) = LibDecimalFloat.unpack(result);
        assertEq(signedCoefficient, signedCoefficientUnpacked);
        assertEq(exponent, exponentUnpacked);
    }

    /// `signedCoefficient` within `maxLift` exponents of the int32 floor.
    function nearTheFloor(int224 signedCoefficient, uint256 lift, uint256 maxLift) internal pure returns (Float) {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exponent = int256(type(int32).min) + int256(bound(lift, 0, maxLift));
        return LibDecimalFloat.packLossless(signedCoefficient, exponent);
    }

    /// Every Float is a whole multiple of 1e-2147483648, so a sum of two is
    /// zero or at least that in magnitude and `add` never reverts
    /// `ExponentUnderflow`. `testAddPacked` in both orders with `a` within ten
    /// exponents of the floor and `b` within eighty, where the fuzzer
    /// otherwise never lands.
    function testAddNearTheFloorNeverUnderflows(int224 coefficientA, int224 coefficientB, uint256 liftA, uint256 liftB)
        external
        view
    {
        Float a = nearTheFloor(coefficientA, liftA, 9);
        Float b = nearTheFloor(coefficientB, liftB, 80);
        checkAddValue(a, b, this.addExternal(a, b));
        checkAddValue(b, a, this.addExternal(b, a));
    }

    /// #350: the oracle accepts the one Float the rule gives and not the
    /// other adjacent one. `1e100 - 1` truncates towards zero to
    /// `(10^67 - 1)e33`, not `1e100`.
    /// `1e76 - 1000000001.5` truncates to `(10^67 - 2)e9`, not
    /// `(10^67 - 1)e9` above it. `1e100 + 1e-100` truncates to `1e100`, not
    /// `(10^67 + 1)e33`.
    function testAddCancelRuleAcceptsOneFloat() external pure {
        Float cancel = LibDecimalFloat.packLossless(1, 100).add(LibDecimalFloat.packLossless(-1, 0));
        assertTrue(cancel.eq(LibDecimalFloat.packLossless(1e67 - 1, 33)), "towards zero");
        assertTrue(LibExactFloat.isSumResult(1, 100, -1, 0, 1e67 - 1, 33), "towards accepted");
        assertFalse(LibExactFloat.isSumResult(1, 100, -1, 0, 1, 100), "away rejected");

        Float toward = LibDecimalFloat.packLossless(1e66, 10).add(LibDecimalFloat.packLossless(-10000000015, -1));
        assertTrue(toward.eq(LibDecimalFloat.packLossless(1e67 - 2, 9)), "towards zero");
        assertTrue(LibExactFloat.isSumResult(1e66, 10, -10000000015, -1, 1e67 - 2, 9), "towards accepted");
        assertFalse(LibExactFloat.isSumResult(1e66, 10, -10000000015, -1, 1e67 - 1, 9), "towards: away rejected");
        assertFalse(LibExactFloat.isSumResult(1e66, 10, -10000000015, -1, 1e67 - 3, 9), "two below");

        Float same = LibDecimalFloat.packLossless(1, 100).add(LibDecimalFloat.packLossless(1, -100));
        assertTrue(same.eq(LibDecimalFloat.packLossless(1, 100)), "same sign");
        assertTrue(LibExactFloat.isSumResult(1, 100, 1, -100, 1, 100), "same sign accepted");
        assertFalse(LibExactFloat.isSumResult(1, 100, 1, -100, 1e67 + 1, 33), "same sign: away rejected");
    }

    function addPartsExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (int256, int256)
    {
        return LibDecimalFloatImplementation.add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// #350: the parts `add` hands to packing are the exact sum rounded as
    /// its NatSpec states.
    function testAddPartsMatchRule(Float a, Float b) external view {
        (int256 signedCoefficientA, int256 exponentA) = LibDecimalFloat.unpack(a);
        (int256 signedCoefficientB, int256 exponentB) = LibDecimalFloat.unpack(b);
        checkAddPartsMatchRule(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// #350: as `testAddPartsMatchRule`, with the operands' digits
    /// overlapping or adjacent.
    function testAddPartsMatchRuleNearby(
        int224 signedCoefficientA,
        int32 exponentA,
        int224 signedCoefficientB,
        uint256 gap
    ) external view {
        int256 exponentB = int256(exponentA) - int256(bound(gap, 0, 100));
        vm.assume(exponentB >= type(int32).min);
        checkAddPartsMatchRule(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// #350: as `testAddPartsMatchRule`, with `a` within two units of `-b`'s
    /// leading digits, so that the sum cancels down to `b`'s trailing digits.
    function testAddPartsMatchRuleCancelling(int224 signedCoefficientB, int32 exponentB, uint256 gap, int256 delta)
        external
        view
    {
        uint256 shed = bound(gap, 0, 68);
        // forge-lint: disable-next-line(unsafe-typecast)
        vm.assume(int256(exponentB) + int256(shed) <= type(int32).max);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedCoefficientA = -(int256(signedCoefficientB) / int256(10 ** shed)) + bound(delta, -2, 2);
        // forge-lint: disable-next-line(unsafe-typecast)
        vm.assume(int224(signedCoefficientA) == signedCoefficientA);
        // forge-lint: disable-next-line(unsafe-typecast)
        checkAddPartsMatchRule(signedCoefficientA, int256(exponentB) + int256(shed), signedCoefficientB, exponentB);
    }

    function checkAddPartsMatchRule(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) internal view {
        (int256 signedCoefficient, int256 exponent) = this.addPartsExternal(
            signedCoefficientA, exponentA, signedCoefficientB, exponentB
        );
        (bool overflowed, int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibExactFloat.addPartsWide(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertFalse(overflowed, "sum past int256 exponent");
        assertEq(signedCoefficient, expectedSignedCoefficient, "coefficient");
        assertEq(exponent, expectedExponent, "exponent");
    }

    /// Magnitudes add, so `1e100 + 1e-100` truncates towards zero.
    function testAddRoundingSameSign() external pure {
        Float sum = LibDecimalFloat.packLossless(1, 100).add(LibDecimalFloat.packLossless(1, -100));
        assertTrue(sum.eq(LibDecimalFloat.packLossless(1, 100)));
        sum = LibDecimalFloat.packLossless(-1, 100).add(LibDecimalFloat.packLossless(-1, -100));
        assertTrue(sum.eq(LibDecimalFloat.packLossless(-1, 100)));
    }

    /// #350: magnitudes cancel, and `1e100 - 1` truncates towards zero to
    /// `(1e67 - 1)e33`.
    function testAddRoundingCancelTowardsZero() external pure {
        Float sum = LibDecimalFloat.packLossless(1, 100).add(LibDecimalFloat.packLossless(-1, 0));
        assertTrue(sum.eq(LibDecimalFloat.packLossless(1e67 - 1, 33)));
        sum = LibDecimalFloat.packLossless(-1, 100).add(LibDecimalFloat.packLossless(1, 0));
        assertTrue(sum.eq(LibDecimalFloat.packLossless(-(1e67 - 1), 33)));
    }

    /// #350: `1e100 - (1e33 + 1)` truncates towards zero to `1e100 - 2e33`.
    function testAddRoundingCancelPartialDigit() external pure {
        Float sum = LibDecimalFloat.packLossless(1, 100).add(LibDecimalFloat.packLossless(-(1e33 + 1), 0));
        assertTrue(sum.eq(LibDecimalFloat.packLossless(1e67 - 2, 33)));
    }

    /// `1e100 - 1.7e33` and `1e100 - (1.5e33 + 1)` both truncate towards zero
    /// to `1e100 - 2e33`.
    function testAddRoundingCancelPartialDigitTowardsZero() external pure {
        Float sum = LibDecimalFloat.packLossless(1, 100).add(LibDecimalFloat.packLossless(-17, 32));
        assertTrue(sum.eq(LibDecimalFloat.packLossless(1e67 - 2, 33)));
        sum = LibDecimalFloat.packLossless(1, 100).add(LibDecimalFloat.packLossless(-(15e32 + 1), 0));
        assertTrue(sum.eq(LibDecimalFloat.packLossless(1e67 - 2, 33)));
    }

    /// #332: int224.max + 1 is 2^223, which packs as int224.max at the same
    /// exponent, so adding a positive number does not lower the value.
    function testAddInt224MaxPlusOne() external pure {
        Float max = LibDecimalFloat.packLossless(type(int224).max, 0);
        Float sum = max.add(LibDecimalFloat.packLossless(1, 0));
        assertEq(Float.unwrap(sum), Float.unwrap(max));
        assertEq(Float.unwrap(max.add(LibDecimalFloat.packLossless(2, 0))), Float.unwrap(max));
        Float min = LibDecimalFloat.packLossless(type(int224).min, -7);
        assertEq(Float.unwrap(min.add(LibDecimalFloat.packLossless(-1, -7))), Float.unwrap(min));
    }
}
