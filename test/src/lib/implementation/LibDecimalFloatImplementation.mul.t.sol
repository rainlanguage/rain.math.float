// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {
    LibDecimalFloatImplementation,
    EXPONENT_MIN,
    EXPONENT_MAX,
    NORMALIZED_ZERO_SIGNED_COEFFICIENT,
    NORMALIZED_ZERO_EXPONENT
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Test} from "forge-std/Test.sol";
import {LibDecimalFloatSlow} from "test/lib/LibDecimalFloatSlow.sol";

contract LibDecimalFloatImplementationMulTest is Test {
    /// Simple 0 multiply 0
    /// 0 * 0 = 0
    function testMulZero0Exponent() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.mul(0, 0, 0, 0);
        assertEq(signedCoefficient, NORMALIZED_ZERO_SIGNED_COEFFICIENT);
        assertEq(exponent, NORMALIZED_ZERO_EXPONENT);
    }

    /// 0 multiply 0 any exponent
    /// 0 * 0 = 0
    function testMulZeroAnyExponent(int64 exponentA, int64 exponentB) external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.mul(0, exponentA, 0, exponentB);
        assertEq(signedCoefficient, NORMALIZED_ZERO_SIGNED_COEFFICIENT);
        assertEq(exponent, NORMALIZED_ZERO_EXPONENT);
    }

    /// 0 multiply 1
    /// 0 * 1 = 0
    function testMulZeroOne() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.mul(0, 0, 1, 0);
        assertEq(signedCoefficient, NORMALIZED_ZERO_SIGNED_COEFFICIENT);
        assertEq(exponent, NORMALIZED_ZERO_EXPONENT);
    }

    /// 1 multiply 0
    /// 1 * 0 = 0
    function testMulOneZero() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.mul(1, 0, 0, 0);
        assertEq(signedCoefficient, NORMALIZED_ZERO_SIGNED_COEFFICIENT);
        assertEq(exponent, NORMALIZED_ZERO_EXPONENT);
    }

    /// 1 multiply 1
    /// 1 * 1 = 1
    function testMulOneOne() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.mul(1, 0, 1, 0);
        assertEq(signedCoefficient, 1);
        assertEq(exponent, 0);
    }

    /// 123456789 multiply 987654321
    /// 123456789 * 987654321 = 121932631112635269
    function testMul123456789987654321() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.mul(123456789, 0, 987654321, 0);
        assertEq(signedCoefficient, 121932631112635269);
        assertEq(exponent, 0);
    }

    function testMulMaxSignedCoefficient() external pure {
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.mul(type(int256).max, 0, type(int256).max, 0);
        // Numbers checked on desmos.
        assertEq(
            signedCoefficient, int256(3.3519519824856492748935062495514615318698414551480983444308903609304410075182e76)
        );
        assertEq(exponent, 77);
    }

    /// 123456789 multiply 987654321 with exponents
    /// 123456789 * 987654321 = 121932631112635269
    function testMul123456789987654321WithExponents(int128 exponentA, int128 exponentB) external pure {
        exponentA = int128(bound(exponentA, -127, 127));
        exponentB = int128(bound(exponentB, -127, 127));

        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.mul(123456789, exponentA, 987654321, exponentB);
        assertEq(signedCoefficient, 121932631112635269);
        assertEq(exponent, exponentA + exponentB);
    }

    /// 1e18 * 1e-19 = 1e-1
    function testMul1e181e19() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.mul(1, 18, 1, -19);
        assertEq(signedCoefficient, 1);
        assertEq(exponent, -1);
    }

    function testMulGasZero() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.mul(0, 0, 0, 0);
        (signedCoefficient, exponent);
    }

    function testMulGasOne() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.mul(1e37, -37, 1e37, -37);
        (signedCoefficient, exponent);
    }

    function testMulNotRevertAnyExpectation(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) external pure {
        exponentA = bound(exponentA, EXPONENT_MIN, EXPONENT_MAX);
        exponentB = bound(exponentB, EXPONENT_MIN, EXPONENT_MAX);
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.mul(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibDecimalFloatSlow.mulSlow(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        assertEq(signedCoefficient, expectedSignedCoefficient);
        assertEq(exponent, expectedExponent);
    }
}
