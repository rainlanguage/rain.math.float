// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";

import {
    LibDecimalFloatImplementation,
    EXPONENT_MIN,
    EXPONENT_MAX
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibDecimalFloatImplementationSlow} from "../../../lib/implementation/LibDecimalFloatImplementationSlow.sol";

contract LibDecimalFloatImplementationNormalizeTest is Test {
    /// isNormalized reference.
    function testIsNormalizedReference(int256 signedCoefficient, int256 exponent) external pure {
        bool expected = LibDecimalFloatImplementationSlow.isNormalizedSlow(signedCoefficient, exponent);
        bool actual = LibDecimalFloatImplementation.isNormalized(signedCoefficient, exponent);
        assertEq(actual, expected);
    }

    /// Every normalized number is normalized.
    function testNormalized(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, EXPONENT_MIN, EXPONENT_MAX);
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.normalize(signedCoefficient, exponent);
        assertTrue(LibDecimalFloatImplementation.isNormalized(actualSignedCoefficient, actualExponent));
    }

    function checkNormalized(
        int256 signedCoefficient,
        int256 exponent,
        int256 expectedCoefficient,
        int256 expectedExponent
    ) internal pure {
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.normalize(signedCoefficient, exponent);
        assertEq(actualSignedCoefficient, expectedCoefficient);
        assertEq(actualExponent, expectedExponent);
    }

    function testExamples() external pure {
        checkNormalized(0, 0, 0, 0);
        checkNormalized(1e37, 0, 1e37, 0);
        checkNormalized(type(int256).max, 0, 5.7896044618658097711785492504343953926e37, 39);
        checkNormalized(type(int256).min, 0, -5.7896044618658097711785492504343953926e37, 39);
        checkNormalized(42, 0, 42e36, -36);
        checkNormalized(42e36, -36, 42e36, -36);

        for (int256 i = 76; i >= 0; i--) {
            checkNormalized(int256(10 ** uint256(i)), 0, 1e37, i - 37);
        }
    }

    /// Normalization should be idempotent.
    function testIdempotent(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, EXPONENT_MIN, EXPONENT_MAX);
        (int256 normalizedSignedCoefficient, int256 normalizedExponent) =
            LibDecimalFloatImplementation.normalize(signedCoefficient, exponent);
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.normalize(normalizedSignedCoefficient, normalizedExponent);
        assertEq(actualSignedCoefficient, normalizedSignedCoefficient);
        assertEq(actualExponent, normalizedExponent);
    }
}
