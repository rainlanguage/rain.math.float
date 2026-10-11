// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";
import {LibTestRegion} from "test/lib/LibTestRegion.sol";

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
        assertTrue(lte(signedCoefficient, exponent, signedCoefficient, exponent));
    }

    /// Both directions are the exact order of the pair, and `eq` is its
    /// equality.
    function testLteTotalOrder(int256 coefficientA, int256 exponentA, int256 coefficientB, int256 exponentB)
        external
        pure
    {
        checkTotalOrder(coefficientA, exponentA, coefficientB, exponentB);
    }

    /// Both directions are the exact order of the pair, with coefficients of
    /// every digit count at exponents within 76 of each other, where `lte`
    /// rescales.
    function testLteTotalOrderRescaled(
        int256 coefficientA,
        uint256 dropA,
        int256 exponentA,
        int256 coefficientB,
        uint256 dropB,
        int256 offset
    ) external pure {
        checkTotalOrder(
            LibTestRegion.anyDigits(coefficientA, dropA),
            exponentA,
            LibTestRegion.anyDigits(coefficientB, dropB),
            LibTestRegion.nearExponent(exponentA, offset)
        );
    }

    function checkTotalOrder(int256 coefficientA, int256 exponentA, int256 coefficientB, int256 exponentB)
        internal
        pure
    {
        int256 order = LibTestExactDecimal.cmpParts(coefficientA, exponentA, coefficientB, exponentB);
        assertEq(lte(coefficientA, exponentA, coefficientB, exponentB), order <= 0, "forward");
        assertEq(lte(coefficientB, exponentB, coefficientA, exponentA), order >= 0, "backward");
        assertEq(LibDecimalFloatImplementation.eq(coefficientA, exponentA, coefficientB, exponentB), order == 0, "eq");
    }
}
