// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, COMPARE_EQUAL, EXPONENT_MIN, EXPONENT_MAX} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {Test, console2} from "forge-std/Test.sol";

contract LibDecimalFloatDecimalAddTest is Test {
    /// Simple 0 add 0
    /// 0 + 0 = 0
    function testAddZero() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.add(0, 0, 0, 0);
        assertEq(signedCoefficient, 0);
        assertEq(exponent, 0);
    }

    /// 0 add 0 any exponent
    /// 0 + 0 = 0
    function testAddZeroAnyExponent(int128 inputExponent) external pure {
        inputExponent = int128(bound(inputExponent, EXPONENT_MIN, EXPONENT_MAX));
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.add(0, inputExponent, 0, 0);
        assertEq(signedCoefficient, 0);
        assertEq(exponent, 0);
    }

    /// 0 add 1
    /// 0 + 1 = 1
    function testAddZeroOne() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.add(0, 0, 1, 0);
        assertEq(signedCoefficient, 1e37);
        assertEq(exponent, -37);
    }

    /// 1 add 0
    /// 1 + 0 = 1
    function testAddOneZero() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.add(1, 0, 0, 0);
        assertEq(signedCoefficient, 1e37);
        assertEq(exponent, -37);
    }

    /// 1 add 1
    /// 1 + 1 = 2
    function testAddOneOneNotNormalized() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.add(1, 0, 1, 0);
        assertEq(signedCoefficient, 2e37);
        assertEq(exponent, -37);
    }

    function testAddOneOnePreNormalized() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.add(1e37, -37, 1e37, -37);
        assertEq(signedCoefficient, 2e37);
        assertEq(exponent, -37);
    }

    /// 123456789 add 987654321
    /// 123456789 + 987654321 = 1111111110
    function testAdd123456789987654321() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.add(123456789, 0, 987654321, 0);
        assertEq(signedCoefficient, 1.11111111e37);
        assertEq(exponent, -37 + 9);
    }

    /// 123456789e9 add 987654321
    /// 123456789e9 + 987654321 = 123456789987654321
    function testAdd123456789e9987654321() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.add(123456789, 9, 987654321, 0);
        assertEq(signedCoefficient, 1.23456789987654321e37);
        assertEq(exponent, -37 + 17);
    }

    function testGasAddZero() external pure {
        LibDecimalFloat.add(0, 0, 0, 0);
    }

    function testGasAddOne() external pure {
        LibDecimalFloat.add(1e37, -37, 1e37, -37);
    }

    function testAddNeverRevertIsNormalized(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) external pure {
        exponentA = bound(exponentA, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
        exponentB = bound(exponentB, EXPONENT_MIN / 10, EXPONENT_MAX / 10);

        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloat.add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assert(LibDecimalFloatImplementation.isNormalized(signedCoefficient, exponent));
    }

    function testAddingSmallToLargeReturnsLarge(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) external pure {
        exponentA = bound(exponentA, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
        exponentB = bound(exponentB, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
        vm.assume(signedCoefficientA != 0);
        vm.assume(signedCoefficientB != 0);

        (int256 normalizedSignedCoefficientA, int256 normalizedExponentA) =
            LibDecimalFloatImplementation.normalize(signedCoefficientA, exponentA);
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibDecimalFloatImplementation.normalize(signedCoefficientB, exponentB);

        vm.assume(normalizedSignedCoefficientA != 0);
        vm.assume(expectedSignedCoefficient != 0);

        console2.log("normalizedSignedCoefficientA", normalizedSignedCoefficientA);
        console2.log("normalizedExponentA", normalizedExponentA);
        console2.log("expectedSignedCoefficient", expectedSignedCoefficient);
        console2.log("expectedExponent", expectedExponent);

        vm.assume((exponentB - exponentA) > 100);

        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloat.add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(signedCoefficient, expectedSignedCoefficient);
        assertEq(exponent, expectedExponent);
    }
}
