// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, EXPONENT_MIN, EXPONENT_MAX, ADD_MAX_EXPONENT_DIFF, Float} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatDecimalAddTest is Test {
    using LibDecimalFloat for Float;

    function addExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (int256, int256)
    {
        return LibDecimalFloat.add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    function addExternal(Float memory a, Float memory b) external pure returns (int256, int256) {
        return LibDecimalFloat.add(a.signedCoefficient, a.exponent, b.signedCoefficient, b.exponent);
    }

    /// Stack and mem are the same.
    function testAddMem(Float memory a, Float memory b) external {
        try this.addExternal(a.signedCoefficient, a.exponent, b.signedCoefficient, b.exponent) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            Float memory resultMem = a.add(b);
            assertEq(signedCoefficient, resultMem.signedCoefficient);
            assertEq(exponent, resultMem.exponent);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            a.add(b);
        }
    }

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
        assertEq(signedCoefficient, 1);
        assertEq(exponent, 0);
    }

    /// 1 add 0
    /// 1 + 0 = 1
    function testAddOneZero() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.add(1, 0, 0, 0);
        assertEq(signedCoefficient, 1);
        assertEq(exponent, 0);
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
        assertEq(signedCoefficient, 1.11111111e38);
        assertEq(exponent, -38 + 9);
    }

    /// 123456789e9 add 987654321
    /// 123456789e9 + 987654321 = 123456789987654321
    function testAdd123456789e9987654321() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.add(123456789, 9, 987654321, 0);
        assertEq(signedCoefficient, 1.23456789987654321e46);
        assertEq(exponent, -46 + 17);
    }

    function testGasAddZero() external pure {
        LibDecimalFloat.add(0, 0, 0, 0);
    }

    function testGasAddOne() external pure {
        LibDecimalFloat.add(1e37, -37, 1e37, -37);
    }

    /// Provided our exponents are in range we should never revert.
    function testAddNeverRevert(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) external pure {
        exponentA = bound(exponentA, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
        exponentB = bound(exponentB, EXPONENT_MIN / 10, EXPONENT_MAX / 10);

        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloat.add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (signedCoefficient, exponent);
    }

    function testAddingSmallToLargeReturnsLargeFuzz(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) public pure {
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

        vm.assume((expectedExponent - normalizedExponentA) > int256(ADD_MAX_EXPONENT_DIFF));

        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloat.add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(signedCoefficient, expectedSignedCoefficient);
        assertEq(exponent, expectedExponent);
    }

    function testAddingSmallToLargeReturnsLargeExamples() external pure {
        // Establish a baseline.
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.add(1e37, 0, 1e37, -37);
        assertEq(signedCoefficient, 10000000000000000000000000000000000001e37);
        assertEq(exponent, -37);
        // Show baseline with reversed order.
        (signedCoefficient, exponent) = LibDecimalFloat.add(1e37, -37, 1e37, 0);
        assertEq(signedCoefficient, 10000000000000000000000000000000000001e37);
        assertEq(exponent, -37);

        // Show full precision loss.
        (signedCoefficient, exponent) = LibDecimalFloat.add(1e37, 0, 1e37, -38);
        assertEq(signedCoefficient, 1e37);
        assertEq(exponent, 0);
        // Show same thing again with reversed order.
        (signedCoefficient, exponent) = LibDecimalFloat.add(1e37, -38, 1e37, 0);
        assertEq(signedCoefficient, 1e37);
        assertEq(exponent, 0);

        // Same precision loss happens for negative numbers.
        (signedCoefficient, exponent) = LibDecimalFloat.add(-1e37, 0, -1e37, -38);
        assertEq(signedCoefficient, -1e37);
        assertEq(exponent, 0);
        // Reverse order.
        (signedCoefficient, exponent) = LibDecimalFloat.add(-1e37, -38, -1e37, 0);
        assertEq(signedCoefficient, -1e37);
        assertEq(exponent, 0);

        // Only the difference in exponents matters. Show the baseline.
        (signedCoefficient, exponent) = LibDecimalFloat.add(1e37, -20, 1e37, -57);
        assertEq(signedCoefficient, 10000000000000000000000000000000000001e37);
        assertEq(exponent, -57);
        // Reverse order.
        (signedCoefficient, exponent) = LibDecimalFloat.add(1e37, -57, 1e37, -20);
        assertEq(signedCoefficient, 10000000000000000000000000000000000001e37);
        assertEq(exponent, -57);

        // Only the difference in exponents matters.
        (signedCoefficient, exponent) = LibDecimalFloat.add(1e37, -20, 1e37, -58);
        assertEq(signedCoefficient, 1e37);
        assertEq(exponent, -20);
        // Reverse order.
        (signedCoefficient, exponent) = LibDecimalFloat.add(1e37, -58, 1e37, -20);
        assertEq(signedCoefficient, 1e37);

        // Only the difference in exponents matters. Show negative numbers.
        (signedCoefficient, exponent) = LibDecimalFloat.add(-1e37, -20, -1e37, -58);
        assertEq(signedCoefficient, -1e37);
        assertEq(exponent, -20);
        // Reverse order.
        (signedCoefficient, exponent) = LibDecimalFloat.add(-1e37, -58, -1e37, -20);
        assertEq(signedCoefficient, -1e37);
    }

    /// If the exponents are the same and the coefficients are the same, then
    /// addition is simply adding the coefficients.
    function testAddSameExponentSameCoefficient(int256 signedCoefficientA, int256 signedCoefficientB) external pure {
        int256 exponentA;
        int256 exponentB;
        (signedCoefficientA, exponentA) = LibDecimalFloatImplementation.normalize(signedCoefficientA, 0);
        (signedCoefficientB, exponentB) = LibDecimalFloatImplementation.normalize(signedCoefficientB, 0);

        if (signedCoefficientA == 0 || signedCoefficientB == 0) {
            exponentA = 0;
        }
        exponentB = exponentA;

        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloat.add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        int256 expectedSignedCoefficient = signedCoefficientA + signedCoefficientB;
        int256 expectedExponent = exponentA;

        assertEq(signedCoefficient, expectedSignedCoefficient);
        assertEq(exponent, expectedExponent);
    }

    /// Adding any zero to any value returns the non-zero value.
    function testAddZeroToAnyNonZero(int256 exponentZero, int256 signedCoefficient, int256 exponent) external pure {
        exponentZero = bound(exponentZero, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
        exponent = bound(exponent, EXPONENT_MIN / 10, EXPONENT_MAX / 10);

        vm.assume(signedCoefficient != 0);

        (int256 expectedSignedCoefficient, int256 expectedExponent) = (signedCoefficient, exponent);
        (int256 signedCoefficientAddZero, int256 exponentAddZero) =
            LibDecimalFloat.add(0, exponentZero, signedCoefficient, exponent);
        assertEq(signedCoefficientAddZero, expectedSignedCoefficient);
        assertEq(exponentAddZero, expectedExponent);

        // Reverse order.
        (signedCoefficientAddZero, exponentAddZero) = LibDecimalFloat.add(signedCoefficient, exponent, 0, exponentZero);
        assertEq(signedCoefficientAddZero, expectedSignedCoefficient);
        assertEq(exponentAddZero, expectedExponent);
    }
}
