// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float, ExponentUnderflow} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {DivisionByZero} from "src/error/ErrDecimalFloat.sol";
import {LibTestExactDecimal, U512} from "test/lib/LibTestExactDecimal.sol";

contract LibDecimalFloatInvTest is Test {
    using LibDecimalFloat for Float;

    function invExternal(int256 signedCoefficient, int256 exponent) external pure returns (Float) {
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.inv(signedCoefficient, exponent);
        Float float = LibDecimalFloat.packArithmeticResult(signedCoefficient, exponent);
        return float;
    }

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
    /// producing `FLOAT_ZERO`. `1e67` at the exponent ceiling inverts to
    /// `1e-67` at `-int32.max`, i.e. `1` at `int32.min - 66`: every digit would
    /// have to be shed to reach the floor, so the magnitude is gone. `1e76 ×
    /// 10^-76` over `1e67` maximized to `1e76 × 10^(int32.max - 9)`, scaled by
    /// `1e76`, is `1e76 × 10^(-76 - 76 - (int32.max - 9))`.
    function testInvRevertsOnExponentUnderflow() external {
        Float float = LibDecimalFloat.packLossless(1e67, int256(type(int32).max));
        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, int256(1e76), int256(-2147483790)));
        this.invExternal(float);
    }

    /// Reverts only on zero, or where the exact inverse is below the smallest
    /// positive Float, otherwise is the nearest Float towards zero to the exact
    /// inverse, and agrees with the unpacked path. No inverse overflows: the
    /// smallest magnitude is `1e-2147483648`, whose inverse is
    /// `10 × 10^int32.max`.
    function testInvMem(Float float) external {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        if (signedCoefficient == 0) {
            vm.expectRevert(abi.encodeWithSelector(DivisionByZero.selector, int256(1e76), int256(-76)));
            this.invExternal(float);
            return;
        }
        assertFalse(LibTestExactDecimal.divOverflows(1, 0, signedCoefficient, exponent), "inverse overflows");
        if (LibTestExactDecimal.divUnderflows(1, 0, signedCoefficient, exponent)) {
            (int256 signedCoefficientInv, int256 exponentInv) =
                LibTestExactDecimal.invPayload(signedCoefficient, exponent);
            vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, signedCoefficientInv, exponentInv));
            this.invExternal(float);
            return;
        }
        Float floatParts = this.invExternal(signedCoefficient, exponent);
        (int256 signedCoefficientResult, int256 exponentResult) = floatParts.unpack();
        Float floatInv = this.invExternal(float);
        (int256 signedCoefficientResultUnpacked, int256 exponentResultUnpacked) = floatInv.unpack();
        assertEq(signedCoefficientResultUnpacked, signedCoefficientResult);
        assertEq(exponentResultUnpacked, exponentResult);
        (U512 memory magnitude, int256 exponentExact) = LibTestExactDecimal.quotient(1, 0, signedCoefficient, exponent);
        assertTrue(
            LibTestExactDecimal.isNearestTowardZero(
                signedCoefficient < 0, magnitude, exponentExact, signedCoefficientResultUnpacked, exponentResultUnpacked
            ),
            "nearest Float towards zero"
        );
    }
}
