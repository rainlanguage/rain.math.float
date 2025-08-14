// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {
    LibDecimalFloatImplementation,
    EXPONENT_MIN,
    EXPONENT_MAX,
    ADD_MAX_EXPONENT_DIFF
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatImplementationAddTest is Test {
    function willOverflow(int256 a, int256 b) internal pure returns (bool) {
        unchecked {
            if (a > 0 && b > 0) {
                return a > type(int256).max - b;
            } else if (a < 0 && b < 0) {
                return a < type(int256).min - b;
            } else {
                return false; // No overflow if signs are different.
            }
        }
    }

    /// This is copypasta from the internals of add.
    function willOverflow2(int256 a, int256 b) internal pure returns (bool didOverflow) {
        unchecked {
            int256 c = a + b;
            assembly ("memory-safe") {
                let sameSignAB := iszero(shr(0xff, xor(a, b)))
                let sameSignAC := iszero(shr(0xff, xor(a, c)))
                didOverflow := and(sameSignAB, iszero(sameSignAC))
            }
        }
    }

    function testOverflowChecks(int256 a, int256 b) external pure {
        bool expected = willOverflow(a, b);
        bool actual = willOverflow2(a, b);
        assertEq(actual, expected, "Overflow check mismatch");
    }

    function checkAdd(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal pure {
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(signedCoefficient, expectedSignedCoefficient, "signed coefficient mismatch");
        assertEq(exponent, expectedExponent, "exponent mismatch");
    }

    /// Simple 0 add 0
    /// 0 + 0 = 0
    function testAddZero() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.add(0, 0, 0, 0);
        assertEq(signedCoefficient, 0);
        assertEq(exponent, 0);
    }

    /// 0 add 0 any exponent
    /// 0 + 0 = 0
    function testAddZeroAnyExponent(int128 inputExponent) external pure {
        inputExponent = int128(bound(inputExponent, EXPONENT_MIN, EXPONENT_MAX));
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.add(0, inputExponent, 0, 0);
        assertEq(signedCoefficient, 0);
        assertEq(exponent, 0);
    }

    /// 0 add 1
    /// 0 + 1 = 1
    function testAddZeroOne() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.add(0, 0, 1, 0);
        assertEq(signedCoefficient, 1);
        assertEq(exponent, 0);
    }

    /// 1 add 0
    /// 1 + 0 = 1
    function testAddOneZero() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.add(1, 0, 0, 0);
        assertEq(signedCoefficient, 1);
        assertEq(exponent, 0);
    }

    /// 1 add 1
    /// 1 + 1 = 2
    function testAddOneOneNotMaximized() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.add(1, 0, 1, 0);
        assertEq(signedCoefficient, 2e76, "Signed coefficient mismatch");
        assertEq(exponent, -76, "Exponent mismatch");
    }

    function testAddOneOnePreMaximized() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.add(1e76, -76, 1e76, -76);
        assertEq(signedCoefficient, 2e76);
        assertEq(exponent, -76);
    }

    /// 123456789 add 987654321
    /// 123456789 + 987654321 = 1111111110
    function testAdd123456789987654321() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.add(123456789, 0, 987654321, 0);
        assertEq(signedCoefficient, 1.11111111e76);
        assertEq(exponent, -76 + 9);
    }

    /// 123456789e9 add 987654321
    /// 123456789e9 + 987654321 = 123456789987654321
    function testAdd123456789e9987654321() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.add(123456789, 9, 987654321, 0);
        assertEq(signedCoefficient, 1.23456789987654321e76);
        assertEq(exponent, -76 + 17);
    }

    function testGasAddZero() external pure {
        LibDecimalFloatImplementation.add(0, 0, 0, 0);
    }

    function testGasAddOne() external pure {
        LibDecimalFloatImplementation.add(1e37, -37, 1e37, -37);
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
            LibDecimalFloatImplementation.add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
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
            LibDecimalFloatImplementation.maximize(signedCoefficientA, exponentA);
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibDecimalFloatImplementation.maximize(signedCoefficientB, exponentB);

        vm.assume(normalizedSignedCoefficientA != 0);
        vm.assume(expectedSignedCoefficient != 0);

        vm.assume((expectedExponent - normalizedExponentA) > int256(ADD_MAX_EXPONENT_DIFF));

        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(signedCoefficient, expectedSignedCoefficient);
        assertEq(exponent, expectedExponent);
    }

    function testAddingSmallToLargeReturnsLargeExamples() external pure {
        // Establish a baseline.
        checkAdd(1e37, 0, 1e37, -37, 10000000000000000000000000000000000001e39, -39);
        // Show baseline with reversed order.
        checkAdd(1e37, -37, 1e37, 0, 10000000000000000000000000000000000001e39, -39);

        // Show full precision loss.
        checkAdd(1e37, 0, 1e37, -38, 100000000000000000000000000000000000001e38, -39);
        checkAdd(1e37, 0, 1e37, -75, 10000000000000000000000000000000000000000000000000000000000000000000000000010, -39);
        checkAdd(1e38, 0, 1e37, -76, 1e76, -38);
        checkAdd(1e37, 0, 1e37, -76, 10000000000000000000000000000000000000000000000000000000000000000000000000001, -39);
        // Show same thing again with reversed order.
        checkAdd(1e37, -38, 1e37, 0, 100000000000000000000000000000000000001e38, -39);
        checkAdd(1e37, -75, 1e37, 0, 10000000000000000000000000000000000000000000000000000000000000000000000000010, -39);
        checkAdd(1e37, -76, 1e37, 0, 10000000000000000000000000000000000000000000000000000000000000000000000000001, -39);

        // Same precision loss happens for negative numbers.
        checkAdd(-1e37, 0, -1e37, -38, -100000000000000000000000000000000000001e38, -39);
        checkAdd(
            -1e37, 0, -1e37, -75, -10000000000000000000000000000000000000000000000000000000000000000000000000010, -39
        );
        checkAdd(
            -1e37, 0, -1e37, -76, -10000000000000000000000000000000000000000000000000000000000000000000000000001, -39
        );
        // Reverse order.
        checkAdd(-1e37, -38, -1e37, 0, -100000000000000000000000000000000000001e38, -39);
        checkAdd(
            -1e37, -75, -1e37, 0, -10000000000000000000000000000000000000000000000000000000000000000000000000010, -39
        );
        checkAdd(
            -1e37, -76, -1e37, 0, -10000000000000000000000000000000000000000000000000000000000000000000000000001, -39
        );

        // Only the difference in exponents matters. Show the baseline.
        checkAdd(1e37, -20, 1e37, -57, 10000000000000000000000000000000000001e39, -59);
        checkAdd(
            1e37, -20, 1e37, -95, 10000000000000000000000000000000000000000000000000000000000000000000000000010, -59
        );
        checkAdd(
            1e37, -20, 1e37, -96, 10000000000000000000000000000000000000000000000000000000000000000000000000001, -59
        );
        checkAdd(1e37, -20, 1e37, -97, 1e76, -59);
        // Reverse order.
        checkAdd(1e37, -57, 1e37, -20, 10000000000000000000000000000000000001e39, -59);
        checkAdd(
            1e37, -95, 1e37, -20, 10000000000000000000000000000000000000000000000000000000000000000000000000010, -59
        );
        checkAdd(
            1e37, -96, 1e37, -20, 10000000000000000000000000000000000000000000000000000000000000000000000000001, -59
        );
        checkAdd(1e37, -97, 1e37, -20, 1e76, -59);

        // Show the same thing with negative numbers.
        checkAdd(-1e37, -20, -1e37, -57, -10000000000000000000000000000000000001e39, -59);
        checkAdd(
            -1e37, -20, -1e37, -95, -10000000000000000000000000000000000000000000000000000000000000000000000000010, -59
        );
        checkAdd(
            -1e37, -20, -1e37, -96, -10000000000000000000000000000000000000000000000000000000000000000000000000001, -59
        );
        checkAdd(-1e37, -20, -1e37, -97, -1e76, -59);

        // Reverse order.
        checkAdd(-1e37, -57, -1e37, -20, -10000000000000000000000000000000000001e39, -59);
        checkAdd(
            -1e37, -95, -1e37, -20, -10000000000000000000000000000000000000000000000000000000000000000000000000010, -59
        );
        checkAdd(
            -1e37, -96, -1e37, -20, -10000000000000000000000000000000000000000000000000000000000000000000000000001, -59
        );
        checkAdd(-1e37, -97, -1e37, -20, -1e76, -59);

        // Suspicious values flagged in fuzzing elsewhere.
        checkAdd(54304950862250382, -16, 1e76, -76, 6.4304950862250382e75, -75);
    }

    /// If the exponents are the same then addition is simply adding the
    /// coefficients.
    function testAddSameExponent(int256 signedCoefficientA, int256 signedCoefficientB) external pure {
        int256 exponentA;
        int256 exponentB;
        int256 signedCoefficientAMaximized;
        int256 signedCoefficientBMaximized;
        (signedCoefficientAMaximized, exponentA) = LibDecimalFloatImplementation.maximize(signedCoefficientA, 0);
        (signedCoefficientBMaximized, exponentB) = LibDecimalFloatImplementation.maximize(signedCoefficientB, 0);

        if (signedCoefficientA == 0 || signedCoefficientB == 0) {
            exponentA = 0;
        }
        exponentB = exponentA;

        int256 expectedSignedCoefficient;
        unchecked {
            expectedSignedCoefficient = signedCoefficientAMaximized + signedCoefficientBMaximized;
            // We aren't testing the overflow case in this test.
            vm.assume(!willOverflow(signedCoefficientAMaximized, signedCoefficientBMaximized));
        }
        int256 expectedExponent = exponentA;

        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.add(
            signedCoefficientAMaximized, exponentA, signedCoefficientBMaximized, exponentB
        );

        assertEq(signedCoefficient, expectedSignedCoefficient, "signed coefficient mismatch");
        assertEq(exponent, expectedExponent, "exponent mismatch");
    }

    /// Adding any zero to any value returns the non-zero value.
    function testAddZeroToAnyNonZero(int256 exponentZero, int256 signedCoefficient, int256 exponent) external pure {
        exponentZero = bound(exponentZero, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
        exponent = bound(exponent, EXPONENT_MIN / 10, EXPONENT_MAX / 10);

        vm.assume(signedCoefficient != 0);

        (int256 expectedSignedCoefficient, int256 expectedExponent) = (signedCoefficient, exponent);
        (int256 signedCoefficientAddZero, int256 exponentAddZero) =
            LibDecimalFloatImplementation.add(0, exponentZero, signedCoefficient, exponent);
        assertEq(signedCoefficientAddZero, expectedSignedCoefficient);
        assertEq(exponentAddZero, expectedExponent);

        // Reverse order.
        (signedCoefficientAddZero, exponentAddZero) =
            LibDecimalFloatImplementation.add(signedCoefficient, exponent, 0, exponentZero);
        assertEq(signedCoefficientAddZero, expectedSignedCoefficient);
        assertEq(exponentAddZero, expectedExponent);
    }
}
