// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";

import {
    LibDecimalFloatImplementation,
    EXPONENT_MIN,
    EXPONENT_MAX,
    MAXIMIZED_ZERO_EXPONENT,
    MAXIMIZED_ZERO_SIGNED_COEFFICIENT
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

contract LibDecimalFloatImplementationMaximizeTest is Test {
    function isMaximized(int256 signedCoefficient, int256 exponent) internal pure returns (bool) {
        if (signedCoefficient == 0) {
            return exponent == MAXIMIZED_ZERO_EXPONENT && signedCoefficient == MAXIMIZED_ZERO_SIGNED_COEFFICIENT;
        }

        if (signedCoefficient / 1e76 != 0) {
            return false;
        }

        if (signedCoefficient / 1e75 == 0) {
            return false;
        }

        return true;
    }

    /// Every normalized number is maximized.
    function testMaximized(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, EXPONENT_MIN, EXPONENT_MAX);
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.maximize(signedCoefficient, exponent);
        assertTrue(isMaximized(actualSignedCoefficient, actualExponent));
    }

    function checkMaximized(
        int256 signedCoefficient,
        int256 exponent,
        int256 expectedCoefficient,
        int256 expectedExponent
    ) internal pure {
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.maximize(signedCoefficient, exponent);
        assertEq(actualSignedCoefficient, expectedCoefficient);
        assertEq(actualExponent, expectedExponent);
    }

    function testMaximizedExamples() external pure {
        checkMaximized(0, 0, 0, 0);
        checkMaximized(0, 1, 0, 0);
        checkMaximized(1e37, 0, 1e75, -38);
        checkMaximized(1e75, 0, 1e75, 0);
        checkMaximized(type(int256).max, 0, type(int256).max / 10, 1);
        checkMaximized(type(int256).min, 0, type(int256).min / 10, 1);
        checkMaximized(42, 0, 42e74, -74);
        checkMaximized(42e74, -74, 42e74, -74);

        for (int256 i = 76; i >= 0; i--) {
            checkMaximized(int256(10 ** uint256(i)), 0, 1e75, i - 75);
        }
    }

    /// Maximization should be idempotent.
    function testMaximizedIdempotent(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, EXPONENT_MIN, EXPONENT_MAX);
        (int256 maximizedSignedCoefficient, int256 maximizedExponent) =
            LibDecimalFloatImplementation.maximize(signedCoefficient, exponent);
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.maximize(maximizedSignedCoefficient, maximizedExponent);
        assertEq(actualSignedCoefficient, maximizedSignedCoefficient);
        assertEq(actualExponent, maximizedExponent);
    }
}
