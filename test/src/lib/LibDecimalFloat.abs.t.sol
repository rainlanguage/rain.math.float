// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";

contract LibDecimalFloatAbsTest is Test {
    using LibDecimalFloat for Float;

    /// Anything positive is identity.
    function testAbsPositive(int256 signedCoefficient, int32 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, 1, type(int224).max);
        Float float = LibDecimalFloat.packLossless(signedCoefficient, exponent);
        assertEq(Float.unwrap(float.abs()), Float.unwrap(float));
    }

    /// Zero at any exponent is `FLOAT_ZERO`.
    function testAbsZero(uint32 exponent) external pure {
        Float zero = Float.wrap(bytes32(uint256(exponent) << 224));
        assertEq(Float.unwrap(zero.abs()), Float.unwrap(LibDecimalFloat.FLOAT_ZERO));
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

    function checkAbsInt224Min(int256 exponent) internal pure {
        Float result = LibDecimalFloat.packLossless(type(int224).min, exponent).abs();
        (int256 signedCoefficient, int256 resultExponent) = result.unpack();
        assertEq(signedCoefficient, type(int224).max);
        assertEq(resultExponent, exponent);
    }

    /// An int224.min coefficient becomes int224.max at the same exponent.
    function testAbsInt224Min() external pure {
        checkAbsInt224Min(type(int32).min);
        checkAbsInt224Min(-18);
        checkAbsInt224Min(-1);
        checkAbsInt224Min(0);
        checkAbsInt224Min(1);
        checkAbsInt224Min(18);
        checkAbsInt224Min(type(int32).max);
    }

    /// The nearest Float towards zero to the exact magnitude.
    function testAbsValue(Float float) external pure {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        (int256 signedCoefficientAbs, int256 exponentAbs) = float.abs().unpack();
        assertTrue(
            LibTestExactDecimal.isNearestTowardZero(
                false,
                LibTestExactDecimal.u512(LibTestExactDecimal.abs(signedCoefficient)),
                exponent,
                signedCoefficientAbs,
                exponentAbs
            ),
            "nearest Float towards zero"
        );
    }
}
