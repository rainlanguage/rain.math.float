// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float, ExponentUnderflow} from "src/lib/LibDecimalFloat.sol";
import {DivisionByZero} from "src/error/ErrDecimalFloat.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";

contract LibDecimalFloatInvTest is Test {
    using LibDecimalFloat for Float;

    function invExternal(Float float) external pure returns (Float) {
        return LibDecimalFloat.inv(float);
    }

    /// `inv` of `-1e2147483647` (coefficient -1 at the exponent ceiling) is
    /// `-1e-2147483647`, which is representable: one above the floor. The
    /// implementation produces it maximised, as a ~1e76 coefficient far below
    /// the floor, and the packer must shed the trailing zeros to get back to
    /// it rather than revert (issue #271, the `inv` shape). Before the fix this
    /// test pinned the revert.
    function testInvAtTheExponentCeilingIsRepresentable() external view {
        Float float = Float.wrap(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        assertEq(signedCoefficient, -1, "premise coefficient");
        assertEq(exponent, int256(type(int32).max), "premise exponent");

        Float inverse = this.invExternal(float);
        assertTrue(
            inverse.eq(LibDecimalFloat.packLossless(-1, -int256(type(int32).max))), "inverse is not -1e-2147483647"
        );
        // The packer sheds only as many digits as reaching the floor needs and
        // does not canonicalise, so the representation is -10 AT the floor
        // rather than -1 one above it.
        (signedCoefficient, exponent) = inverse.unpack();
        assertEq(signedCoefficient, -10, "coefficient");
        assertEq(exponent, int256(type(int32).min), "exponent");
    }

    /// `inv` of a Float whose inverse magnitude is genuinely below any
    /// representable Float reverts `ExponentUnderflow` instead of silently
    /// producing `FLOAT_ZERO`, reporting the input. `1e67` at the exponent
    /// ceiling inverts to `1e-67` at `-int32.max`, i.e. `1` at
    /// `int32.min - 66`.
    function testInvRevertsOnExponentUnderflow() external {
        Float float = LibDecimalFloat.packLossless(1e67, int256(type(int32).max));
        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, int256(1e67), int256(type(int32).max)));
        this.invExternal(float);
    }

    /// The least magnitude, `1e-2147483648`, inverts to `10 10^int32.max`, the
    /// largest inverse, for both signs.
    function testInvOfTheLeastMagnitude(bool negative) external view {
        int256 sign = negative ? int256(-1) : int256(1);
        Float inverse = this.invExternal(LibDecimalFloat.packLossless(sign, type(int32).min));
        (int256 signedCoefficient, int256 exponent) = inverse.unpack();
        assertEq(signedCoefficient, sign * 10, "coefficient");
        assertEq(exponent, int256(type(int32).max), "exponent");
    }

    /// Every zero reverts `DivisionByZero` with itself, whatever its exponent.
    function testInvZeroReportsTheInput(int32 exponent) external {
        vm.expectRevert(abi.encodeWithSelector(DivisionByZero.selector, int256(0), int256(exponent)));
        this.invExternal(LibDecimalFloat.packLossless(0, exponent));
    }

    /// Reverts only on zero, or where the exact inverse is below the smallest
    /// positive Float, with the input as the range error's payload. Otherwise
    /// the inverse is the Float closest to the exact one that does not exceed
    /// its magnitude: the exact inverse to 76 digits, packed. No inverse
    /// overflows.
    function testInvMem(Float float) external {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        if (signedCoefficient == 0) {
            vm.expectRevert(abi.encodeWithSelector(DivisionByZero.selector, signedCoefficient, exponent));
            this.invExternal(float);
            return;
        }
        assertFalse(LibTestExactDecimal.divOverflows(1, 0, signedCoefficient, exponent), "inverse overflows");
        if (LibTestExactDecimal.divUnderflows(1, 0, signedCoefficient, exponent)) {
            vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, signedCoefficient, exponent));
            this.invExternal(float);
            return;
        }
        (int256 signedCoefficientExact, int256 exponentExact) =
            LibTestExactDecimal.quotient76(1, 0, signedCoefficient, exponent);
        (Float expected,) = LibDecimalFloat.packLossy(signedCoefficientExact, exponentExact);
        assertEq(Float.unwrap(this.invExternal(float)), Float.unwrap(expected), "inverse");
    }
}
