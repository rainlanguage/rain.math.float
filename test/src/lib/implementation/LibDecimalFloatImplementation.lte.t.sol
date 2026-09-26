// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

contract LibDecimalFloatImplementationLteTest is Test {
    function lte(int256 coefficientA, int256 exponentA, int256 coefficientB, int256 exponentB)
        internal
        pure
        returns (bool)
    {
        return LibDecimalFloatImplementation.lte(coefficientA, exponentA, coefficientB, exponentB);
    }

    /// Same exponent reduces to comparing coefficients.
    function testLteSameExponent() external pure {
        assertTrue(lte(1, 0, 2, 0));
        assertTrue(lte(2, 0, 2, 0));
        assertFalse(lte(3, 0, 2, 0));
        assertTrue(lte(-2, 0, -1, 0));
        assertFalse(lte(-1, 0, -2, 0));
    }

    /// THE POINT OF THE FUNCTION: different exponents are rescaled before
    /// comparing, so a smaller coefficient can be the larger value.
    function testLteDifferentExponents() external pure {
        // 1e1 == 10 > 9e0, despite the coefficient being smaller.
        assertFalse(lte(1, 1, 9, 0));
        assertTrue(lte(9, 0, 1, 1));
        // 1e-1 == 0.1 < 1e0.
        assertTrue(lte(1, -1, 1, 0));
        assertFalse(lte(1, 0, 1, -1));
    }

    /// Numerically equal values compare equal whichever way they are packed,
    /// and `lte` holds in both directions.
    function testLteNumericallyEqual() external pure {
        assertTrue(lte(100, 0, 1, 2));
        assertTrue(lte(1, 2, 100, 0));
        assertTrue(lte(10, 1, 100, 0));
        assertTrue(lte(100, 0, 10, 1));
    }

    /// Every value is <= itself.
    function testLteReflexive(int256 signedCoefficient, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, type(int224).min, type(int224).max);
        exponent = bound(exponent, -50, 50);
        assertTrue(lte(signedCoefficient, exponent, signedCoefficient, exponent));
    }

    /// For any pair, at least one direction holds, and both hold only when
    /// they are numerically equal.
    function testLteTotalOrder(int256 coefficientA, int256 exponentA, int256 coefficientB, int256 exponentB)
        external
        pure
    {
        coefficientA = bound(coefficientA, type(int224).min, type(int224).max);
        coefficientB = bound(coefficientB, type(int224).min, type(int224).max);
        exponentA = bound(exponentA, -50, 50);
        exponentB = bound(exponentB, -50, 50);

        bool forward = lte(coefficientA, exponentA, coefficientB, exponentB);
        bool backward = lte(coefficientB, exponentB, coefficientA, exponentA);
        assertTrue(forward || backward);
        assertEq(
            forward && backward, LibDecimalFloatImplementation.eq(coefficientA, exponentA, coefficientB, exponentB)
        );
    }
}
