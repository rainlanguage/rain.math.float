// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {ExponentOverflow, ExponentUnderflow} from "src/error/ErrDecimalFloat.sol";

contract LibDecimalFloatPackArithmeticResultTest is Test {
    using LibDecimalFloat for Float;

    function packArithmeticResultExternal(int256 signedCoefficient, int256 exponent) external pure returns (Float) {
        return LibDecimalFloat.packArithmeticResult(signedCoefficient, exponent);
    }

    /// Inputs that fit losslessly round-trip through pack and unpack.
    function testPackArithmeticResultLossless(int224 signedCoefficient, int32 exponent) external pure {
        vm.assume(signedCoefficient != 0);
        Float c = LibDecimalFloat.packArithmeticResult(signedCoefficient, exponent);
        (int256 unpackedCoefficient, int256 unpackedExponent) = c.unpack();
        assertEq(unpackedCoefficient, int256(signedCoefficient));
        assertEq(unpackedExponent, int256(exponent));
    }

    /// Coefficients beyond int224 are silently truncated (the order of
    /// magnitude survives the precision loss). The packing does not revert.
    function testPackArithmeticResultToleratesCoefficientTruncation() external pure {
        int256 signedCoefficient = int256(type(int224).max) * 100;
        int256 exponent = 0;
        Float c = LibDecimalFloat.packArithmeticResult(signedCoefficient, exponent);
        (int256 unpackedCoefficient, int256 unpackedExponent) = c.unpack();
        assertGt(unpackedCoefficient, 0);
        assertEq(unpackedExponent, exponent + 2);
    }

    /// Exponents that would underflow int32 after fitting the coefficient
    /// revert with `ExponentUnderflow`. Distinguishes from the coefficient
    /// truncation case where the result is non-zero.
    function testPackArithmeticResultExponentUnderflowReverts() external {
        int256 signedCoefficient = 1;
        int256 exponent = int256(type(int32).min) - 1;
        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, signedCoefficient, exponent));
        this.packArithmeticResultExternal(signedCoefficient, exponent);
    }

    /// Exponents that overflow int32 revert with `ExponentOverflow`,
    /// matching `packLossy`. The underflow path is the only behavioural
    /// divergence from `packLossy`.
    function testPackArithmeticResultExponentOverflowReverts() external {
        int256 signedCoefficient = 1;
        int256 exponent = int256(type(int32).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficient, exponent));
        this.packArithmeticResultExternal(signedCoefficient, exponent);
    }

    /// A zero coefficient is the only legitimate way to produce FLOAT_ZERO
    /// from `packArithmeticResult`. The exponent is ignored.
    function testPackArithmeticResultZeroCoefficient(int256 exponent) external pure {
        Float c = LibDecimalFloat.packArithmeticResult(0, exponent);
        assertEq(Float.unwrap(c), Float.unwrap(LibDecimalFloat.FLOAT_ZERO));
    }
}
