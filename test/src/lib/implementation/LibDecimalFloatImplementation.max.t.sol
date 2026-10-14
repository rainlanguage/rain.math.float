// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "../../../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibExactFloat} from "../../../lib/LibExactFloat.sol";
import {LibTestRegion} from "../../../lib/LibTestRegion.sol";

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

    /// The result is A, unchanged, when A is exactly above B, else B.
    function testMaxIsOneOfTheInputsAndNotLess(
        int256 coefficientA,
        int256 exponentA,
        int256 coefficientB,
        int256 exponentB
    ) external pure {
        checkMax(coefficientA, exponentA, coefficientB, exponentB);
    }

    /// The result is A, unchanged, when A is exactly above B, else B, with
    /// coefficients of every digit count at exponents within 76 of each other,
    /// where `max` rescales.
    function testMaxIsOneOfTheInputsAndNotLessRescaled(
        int256 coefficientA,
        uint256 dropA,
        int256 exponentA,
        int256 coefficientB,
        uint256 dropB,
        int256 offset
    ) external pure {
        checkMax(
            LibTestRegion.anyDigits(coefficientA, dropA),
            exponentA,
            LibTestRegion.anyDigits(coefficientB, dropB),
            LibTestRegion.nearExponent(exponentA, offset)
        );
    }

    function checkMax(int256 coefficientA, int256 exponentA, int256 coefficientB, int256 exponentB) internal pure {
        bool isA = LibExactFloat.cmpParts(coefficientA, exponentA, coefficientB, exponentB) > 0;
        assertMaxIs(
            coefficientA,
            exponentA,
            coefficientB,
            exponentB,
            isA ? coefficientA : coefficientB,
            isA ? exponentA : exponentB
        );
    }

    /// Selecting a larger value is exact — nothing is rescaled into the
    /// result, so the winner comes back byte for byte as it went in.
    function testMaxDoesNotRescaleTheWinner(int256 coefficient, int256 exponent) external pure {
        coefficient = bound(coefficient, 1, type(int256).max);
        // Against a value that is unambiguously smaller.
        assertMaxIs(0, 0, coefficient, exponent, coefficient, exponent);
    }
}
