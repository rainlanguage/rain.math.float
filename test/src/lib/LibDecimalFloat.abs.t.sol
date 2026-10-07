// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {LibDecimalFloat, Float, ExponentOverflow} from "src/lib/LibDecimalFloat.sol";

contract LibDecimalFloatAbsTest is Test {
    using LibDecimalFloat for Float;

    /// Anything non negative is identity.
    function testAbsNonNegative(int256 signedCoefficient, int32 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, 0, type(int224).max);
        Float float = LibDecimalFloat.packLossless(signedCoefficient, exponent);
        Float result = float.abs();
        (int256 resultSignedCoefficient, int256 resultExponent) = LibDecimalFloat.unpack(result);
        assertEq(resultSignedCoefficient, signedCoefficient);
        assertEq(resultExponent, resultSignedCoefficient == 0 ? int256(0) : exponent);
    }

    /// Anything negative is negated. Except for the minimum value.
    function testAbsNegative(int256 signedCoefficient, int32 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, type(int224).min + 1, -1);
        Float float = LibDecimalFloat.packLossless(signedCoefficient, exponent);
        Float result = float.abs();
        (int256 resultSignedCoefficient, int256 resultExponent) = LibDecimalFloat.unpack(result);
        assertEq(resultSignedCoefficient, -signedCoefficient);
        assertEq(resultExponent, exponent);
    }

    function absExternal(Float float) external pure returns (Float) {
        return float.abs();
    }

    /// Minimum value is shifted one OOM. At the exponent ceiling the shift has
    /// nowhere to go, as `2^223 × 10^int32.max` exceeds every Float.
    function testAbsMinValue(int32 exponent) external {
        Float float = LibDecimalFloat.packLossless(type(int224).min, exponent);
        if (exponent == type(int32).max) {
            vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(2 ** 223), int256(exponent)));
            this.absExternal(float);
            return;
        }
        Float result = this.absExternal(float);
        (int256 resultSignedCoefficient, int256 resultExponent) = LibDecimalFloat.unpack(result);
        assertEq(resultSignedCoefficient, -(type(int224).min / 10));
        assertEq(resultExponent, exponent + 1);
    }
}
