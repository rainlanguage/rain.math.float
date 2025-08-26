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
    function checkMul(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal pure {
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.mul(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signedCoefficient");
        assertEq(actualExponent, expectedExponent, "exponent");
    }

    /// -1 * -1 = 1
    function testMulNegativeOne() external pure {
        checkMul(-1, 0, -1, 0, 1, 0);
    }

    /// -1 * 1 = -1
    function testMulNegativeOneOne() external pure {
        checkMul(-1, 0, 1, 0, -1, 0);
    }

    /// 1 * -1 = -1
    function testMulOneNegativeOne() external pure {
        checkMul(1, 0, -1, 0, -1, 0);
    }

    /// found during testing
    /// 1.3979 * 0.5 = 0.69895
    function testMul1_3979_0_5() external pure {
        checkMul(1.3979e76, -76, 0.5e66, -66, 0.69895e76, -76);
    }

    /// Simple 0 multiply 0
    /// 0 * 0 = 0
    function testMulZero0Exponent() external pure {
        checkMul(0, 0, 0, 0, 0, 0);
    }

    /// 0 multiply 0 any exponent
    /// 0 * 0 = 0
    function testMulZeroAnyExponent(int64 exponentA, int64 exponentB) external pure {
        checkMul(0, exponentA, 0, exponentB, 0, 0);
    }

    /// 0 multiply 1
    /// 0 * 1 = 0
    function testMulZeroOne() external pure {
        checkMul(0, 0, 1, 0, 0, 0);
    }

    /// 1 multiply 0
    /// 1 * 0 = 0
    function testMulOneZero() external pure {
        checkMul(1, 0, 0, 0, 0, 0);
    }

    /// 1 multiply 1
    /// 1 * 1 = 1
    function testMulOneOne() external pure {
        checkMul(1, 0, 1, 0, 1, 0);
    }

    /// 123456789 multiply 987654321
    /// 123456789 * 987654321 = 121932631112635269
    function testMul123456789987654321() external pure {
        checkMul(123456789, 0, 987654321, 0, 121932631112635269, 0);
    }

    function testMulMaxSignedCoefficient() external pure {
        checkMul(
            type(int256).max,
            0,
            type(int256).max,
            0,
            int256(3.3519519824856492748935062495514615318698414551480983444308903609304410075182e76),
            77
        );
    }

    /// 123456789 multiply 987654321 with exponents
    /// 123456789 * 987654321 = 121932631112635269
    function testMul123456789987654321WithExponents(int128 exponentA, int128 exponentB) external pure {
        exponentA = int128(bound(exponentA, -127, 127));
        exponentB = int128(bound(exponentB, -127, 127));

        checkMul(123456789, exponentA, 987654321, exponentB, 121932631112635269, exponentA + exponentB);
    }

    /// 1e18 * 1e-19 = 1e-1
    function testMul1e181e19() external pure {
        checkMul(1, 18, 1, -19, 1, -1);
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
        exponentA = bound(exponentA, EXPONENT_MIN, EXPONENT_MAX / 2);
        exponentB = bound(exponentB, EXPONENT_MIN, EXPONENT_MAX / 2);
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.mul(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibDecimalFloatSlow.mulSlow(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        assertEq(signedCoefficient, expectedSignedCoefficient);
        assertEq(exponent, expectedExponent);
    }
}
