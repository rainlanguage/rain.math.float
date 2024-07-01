// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {
    LibDecimalFloat,
    COMPARE_EQUAL,
    NORMALIZED_ZERO_SIGNED_COEFFICIENT,
    NORMALIZED_ZERO_EXPONENT
} from "src/LibDecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatMultiplyTest is Test {
    /// Simple 0 multiply 0
    /// 0 * 0 = 0
    function testMultiplyZero0Exponent() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.multiply(0, 0, 0, 0);
        assertEq(signedCoefficient, NORMALIZED_ZERO_SIGNED_COEFFICIENT);
        assertEq(exponent, NORMALIZED_ZERO_EXPONENT);
    }

    /// 0 multiply 0 any exponent
    /// 0 * 0 = 0
    function testMultiplyZeroAnyExponent(int64 exponentA, int64 exponentB) external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.multiply(0, exponentA, 0, exponentB);
        assertEq(signedCoefficient, NORMALIZED_ZERO_SIGNED_COEFFICIENT);
        assertEq(exponent, NORMALIZED_ZERO_EXPONENT);
    }

    /// 0 multiply 1
    /// 0 * 1 = 0
    function testMultiplyZeroOne() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.multiply(0, 0, 1, 0);
        assertEq(signedCoefficient, NORMALIZED_ZERO_SIGNED_COEFFICIENT);
        assertEq(exponent, NORMALIZED_ZERO_EXPONENT);
    }

    /// 1 multiply 0
    /// 1 * 0 = 0
    function testMultiplyOneZero() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.multiply(1, 0, 0, 0);
        assertEq(signedCoefficient, NORMALIZED_ZERO_SIGNED_COEFFICIENT);
        assertEq(exponent, NORMALIZED_ZERO_EXPONENT);
    }

    /// 1 multiply 1
    /// 1 * 1 = 1
    function testMultiplyOneOne() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.multiply(1, 0, 1, 0);
        assertEq(signedCoefficient, 1e37);
        assertEq(exponent, -37);
    }

    /// 123456789 multiply 987654321
    /// 123456789 * 987654321 = 121932631112635269
    function testMultiply123456789987654321() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.multiply(123456789, 0, 987654321, 0);
        assertEq(signedCoefficient, 1.21932631112635269e37);
        assertEq(exponent, -37 + 17);
    }

    /// 123456789 multiply 987654321 with exponents
    /// 123456789 * 987654321 = 121932631112635269
    function testMultiply123456789987654321WithExponents(int128 exponentA, int128 exponentB) external pure {
        exponentA = int128(bound(exponentA, -127, 127));
        exponentB = int128(bound(exponentB, -127, 127));

        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloat.multiply(123456789, exponentA, 987654321, exponentB);
        assertEq(signedCoefficient, 1.21932631112635269e37);
        assertEq(exponent, -37 + 17 + exponentA + exponentB);
    }

    /// 1e18 * 1e-19 = 1e-1
    function testMultiply1e181e19() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.multiply(1, 18, 1, -19);
        assertEq(signedCoefficient, 1e37);
        assertEq(exponent, -37 - 1);
    }

    function testMultiplyGasZero() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.multiply(0, 0, 0, 0);
        (signedCoefficient, exponent);
    }

    function testMultiplyGasOne() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.multiply(1e37, -37, 1e37, -37);
        (signedCoefficient, exponent);
    }
}
