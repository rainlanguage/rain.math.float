// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

contract LibDecimalFloatImplementationMaxTest is Test {
    function max(int256 coefficientA, int256 exponentA, int256 coefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
        return LibDecimalFloatImplementation.max(coefficientA, exponentA, coefficientB, exponentB);
    }

    function assertMaxIs(
        int256 coefficientA,
        int256 exponentA,
        int256 coefficientB,
        int256 exponentB,
        int256 expectedCoefficient,
        int256 expectedExponent
    ) internal pure {
        (int256 coefficient, int256 exponent) = max(coefficientA, exponentA, coefficientB, exponentB);
        assertEq(coefficient, expectedCoefficient);
        assertEq(exponent, expectedExponent);
    }

    /// Same exponent reduces to comparing coefficients.
    function testMaxSameExponent() external pure {
        assertMaxIs(1, 0, 2, 0, 2, 0);
        assertMaxIs(2, 0, 1, 0, 2, 0);
        assertMaxIs(-2, 0, -1, 0, -1, 0);
    }

    /// THE POINT OF THE FUNCTION: different exponents are rescaled first, so
    /// the larger coefficient is not necessarily the larger value.
    function testMaxDifferentExponents() external pure {
        // 1e1 == 10 beats 9e0, despite the smaller coefficient.
        assertMaxIs(1, 1, 9, 0, 1, 1);
        assertMaxIs(9, 0, 1, 1, 1, 1);
        // 1e-1 == 0.1 loses to 1e0.
        assertMaxIs(1, -1, 1, 0, 1, 0);
    }

    /// Ties return B, so the result is stable regardless of which
    /// representation of a numerically equal pair is passed second.
    function testMaxTiesReturnB() external pure {
        assertMaxIs(100, 0, 1, 2, 1, 2);
        assertMaxIs(1, 2, 100, 0, 100, 0);
    }

    /// The result is always one of the two inputs, and is never less than
    /// either of them.
    function testMaxIsOneOfTheInputsAndNotLess(
        int256 coefficientA,
        int256 exponentA,
        int256 coefficientB,
        int256 exponentB
    ) external pure {
        coefficientA = bound(coefficientA, type(int224).min, type(int224).max);
        coefficientB = bound(coefficientB, type(int224).min, type(int224).max);
        exponentA = bound(exponentA, -50, 50);
        exponentB = bound(exponentB, -50, 50);

        (int256 coefficient, int256 exponent) = max(coefficientA, exponentA, coefficientB, exponentB);

        bool isA = coefficient == coefficientA && exponent == exponentA;
        bool isB = coefficient == coefficientB && exponent == exponentB;
        assertTrue(isA || isB);

        assertTrue(LibDecimalFloatImplementation.lte(coefficientA, exponentA, coefficient, exponent));
        assertTrue(LibDecimalFloatImplementation.lte(coefficientB, exponentB, coefficient, exponent));
    }

    /// Selecting a larger value is exact — nothing is rescaled into the
    /// result, so the winner comes back byte for byte as it went in.
    function testMaxDoesNotRescaleTheWinner(int256 coefficient, int256 exponent) external pure {
        coefficient = bound(coefficient, 1, type(int224).max);
        exponent = bound(exponent, -50, 50);
        // Against a value that is unambiguously smaller.
        assertMaxIs(0, 0, coefficient, exponent, coefficient, exponent);
    }
}
