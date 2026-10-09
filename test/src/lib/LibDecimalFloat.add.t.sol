// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float, ExponentOverflow} from "src/lib/LibDecimalFloat.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";
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

    /// Reverts only where the exact sum is beyond the largest Float of its
    /// sign, and otherwise agrees with the unpacked path.
    function testAddPacked(Float a, Float b) external {
        (int256 signedCoefficientA, int256 exponentA) = LibDecimalFloat.unpack(a);
        (int256 signedCoefficientB, int256 exponentB) = LibDecimalFloat.unpack(b);
        if (LibTestExactDecimal.addOverflows(signedCoefficientA, exponentA, signedCoefficientB, exponentB)) {
            (int256 signedCoefficientSum, int256 exponentSum) =
                LibTestExactDecimal.addParts(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
            vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficientSum, exponentSum));
            this.addExternal(a, b);
            return;
        }
        Float resultParts = this.addExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.unpack(resultParts);
        Float result = this.addExternal(a, b);
        (int256 signedCoefficientUnpacked, int256 exponentUnpacked) = LibDecimalFloat.unpack(result);
        assertEq(signedCoefficient, signedCoefficientUnpacked);
        assertEq(exponent, exponentUnpacked);
    }

    function addPartsExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (int256, int256)
    {
        return LibDecimalFloatImplementation.add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// #340: the parts `add` hands to packing are the exact sum rounded as
    /// its NatSpec states.
    function testAddPartsMatchRule(Float a, Float b) external view {
        (int256 signedCoefficientA, int256 exponentA) = LibDecimalFloat.unpack(a);
        (int256 signedCoefficientB, int256 exponentB) = LibDecimalFloat.unpack(b);
        checkAddPartsMatchRule(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// #340: as `testAddPartsMatchRule`, with the operands' digits
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

    /// #340: as `testAddPartsMatchRule`, with `a` within two units of `-b`'s
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
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibTestExactDecimal.addParts(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(signedCoefficient, expectedSignedCoefficient, "coefficient");
        assertEq(exponent, expectedExponent, "exponent");
    }

    /// #340: magnitudes add, so `1e100 + 1e-100` truncates towards zero.
    function testAddRoundingSameSign() external pure {
        Float sum = LibDecimalFloat.packLossless(1, 100).add(LibDecimalFloat.packLossless(1, -100));
        assertTrue(sum.eq(LibDecimalFloat.packLossless(1, 100)));
        sum = LibDecimalFloat.packLossless(-1, 100).add(LibDecimalFloat.packLossless(-1, -100));
        assertTrue(sum.eq(LibDecimalFloat.packLossless(-1, 100)));
    }

    /// #340: magnitudes cancel, so `1e100 - 1` rounds away from zero at
    /// `1e100`'s unit `1e24`, to `1e100`. Truncating towards zero would give
    /// `(1e67 - 1)e33`.
    function testAddRoundingCancelAway() external pure {
        Float sum = LibDecimalFloat.packLossless(1, 100).add(LibDecimalFloat.packLossless(-1, 0));
        assertTrue(sum.eq(LibDecimalFloat.packLossless(1, 100)));
        sum = LibDecimalFloat.packLossless(-1, 100).add(LibDecimalFloat.packLossless(1, 0));
        assertTrue(sum.eq(LibDecimalFloat.packLossless(-1, 100)));
    }

    /// #340: `1e100 - (1e33 + 1)` rounds away from zero at `1e24` to
    /// `1e100 - 1e33`, which packing keeps: one unit in the last place above
    /// `1e100 - 2e33`, the sum truncated towards zero.
    function testAddRoundingCancelPartialDigitAway() external pure {
        Float sum = LibDecimalFloat.packLossless(1, 100).add(LibDecimalFloat.packLossless(-(1e33 + 1), 0));
        assertTrue(sum.eq(LibDecimalFloat.packLossless(1e67 - 1, 33)));
    }

    /// #340: `1e100 - 1.7e33` and `1e100 - (1.5e33 + 1)` both land at or above
    /// `1e100 - 2e33` after rounding at `1e24`, so packing truncates both to
    /// `1e100 - 2e33`: towards zero, though magnitudes cancel.
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
