// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, COMPARE_EQUAL, COMPARE_GREATER_THAN, COMPARE_LESS_THAN, EXPONENT_MIN, EXPONENT_MAX} from "src/lib/LibDecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatCompareTest is Test {
    /// 1 == 1
    function testCompareOne() external pure {
        int256 compare = LibDecimalFloat.compare(1, 0, 1, 0);
        assertEq(compare, COMPARE_EQUAL);
    }

    /// 10,0 == 1e38,-37
    function testCompareTen() external pure {
        int256 compare = LibDecimalFloat.compare(10, 0, 1e38, -37);
        assertEq(compare, COMPARE_EQUAL);
    }

    /// 1.6e35,-35 > 1.25e37,-37
    function testCompareOnePointSix() external pure {
        int256 compare = LibDecimalFloat.compare(1.6e35, -35, 1.25e37, -37);
        assertEq(compare, COMPARE_GREATER_THAN);
    }

    /// Anything negative is less than anything positive or 0.
    function testCompareNegative(int256 signedCoefficientNeg, int256 exponentNeg, int256 signedCoefficientPos, int256 exponentPos) external pure {
        signedCoefficientNeg = bound(signedCoefficientNeg, type(int256).min, -1);
        signedCoefficientPos = bound(signedCoefficientPos, 0, type(int256).max);
        exponentNeg = bound(exponentNeg, EXPONENT_MIN, EXPONENT_MAX);
        exponentPos = bound(exponentPos, EXPONENT_MIN, EXPONENT_MAX);

        int256 compare = LibDecimalFloat.compare(signedCoefficientNeg, exponentNeg, signedCoefficientPos, exponentPos);
        assertEq(compare, COMPARE_LESS_THAN);
    }

    /// Reversing the order reverses the outcome.
    function testCompareReversed(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB) external pure {
        exponentA = bound(exponentA, EXPONENT_MIN, EXPONENT_MAX);
        exponentB = bound(exponentB, EXPONENT_MIN, EXPONENT_MAX);

        int256 compare0 = LibDecimalFloat.compare(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        int256 compare1 = LibDecimalFloat.compare(signedCoefficientB, exponentB, signedCoefficientA, exponentA);

        if (compare0 == COMPARE_EQUAL) {
            assertEq(compare1, COMPARE_EQUAL);
        } else if (compare0 == COMPARE_GREATER_THAN) {
            assertEq(compare1, COMPARE_LESS_THAN);
        } else {
            assertEq(compare1, COMPARE_GREATER_THAN);
        }
    }

    /// The only possible return values are -1, 0, and 1.
    function testCompareBounds(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB) external pure {
        exponentA = bound(exponentA, EXPONENT_MIN, EXPONENT_MAX);
        exponentB = bound(exponentB, EXPONENT_MIN, EXPONENT_MAX);

        int256 compare = LibDecimalFloat.compare(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assert(compare == COMPARE_LESS_THAN || compare == COMPARE_EQUAL || compare == COMPARE_GREATER_THAN);
    }

    /// Comparing something to itself is always equal.
    function testCompareSelf(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, EXPONENT_MIN, EXPONENT_MAX);

        int256 compare = LibDecimalFloat.compare(signedCoefficient, exponent, signedCoefficient, exponent);
        assertEq(compare, COMPARE_EQUAL);
    }

    /// Two values with the same exponent are compared by their coefficients.
    function testCompareSameExponent(int256 signedCoefficientA, int256 signedCoefficientB, int256 exponent) external pure {
        exponent = bound(exponent, EXPONENT_MIN, EXPONENT_MAX);
        vm.assume(signedCoefficientA != signedCoefficientB);

        int256 compare = LibDecimalFloat.compare(signedCoefficientA, exponent, signedCoefficientB, exponent);
        if (signedCoefficientA < signedCoefficientB) {
            assertEq(compare, COMPARE_LESS_THAN);
        } else if (signedCoefficientA > signedCoefficientB) {
            assertEq(compare, COMPARE_GREATER_THAN);
        } else {
            assertEq(compare, COMPARE_EQUAL);
        }
    }

    /// Anything 0 is always less than anything positive.
    function testCompareZero(int256 signedCoefficient, int256 exponent, int256 exponentZero) external pure {
        signedCoefficient = bound(signedCoefficient, 1, type(int256).max);
        exponent = bound(exponent, EXPONENT_MIN, EXPONENT_MAX);
        exponentZero = bound(exponentZero, EXPONENT_MIN, EXPONENT_MAX);

        int256 compare = LibDecimalFloat.compare(0, exponentZero, signedCoefficient, exponent);
        assertEq(compare, COMPARE_LESS_THAN);
    }
}
