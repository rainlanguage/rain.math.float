// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, COMPARE_LESS_THAN} from "src/lib/LibDecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatLtTest is Test {
    /// Lt and compare need to agree.
    function testLtVsCompare(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
    {
        bool lt = LibDecimalFloat.lt(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        int256 compare = LibDecimalFloat.compare(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        if (compare == COMPARE_LESS_THAN) {
            assertTrue(lt);
        } else {
            assertTrue(!lt);
        }
    }

    // If lt then not equal nor gt.
    function testLtVsEqualVsGt(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
    {
        bool lt = LibDecimalFloat.lt(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        bool equal = LibDecimalFloat.equal(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        bool gt = LibDecimalFloat.gt(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        if (lt) {
            assertTrue(!equal);
            assertTrue(!gt);
        } else {
            assertTrue(equal || gt);
        }
    }

    function testLtGasDifferentSigns() external pure {
        LibDecimalFloat.lt(1, 0, -1, 0);
    }

    function testLtGasAZero() external pure {
        LibDecimalFloat.compare(0, 0, 1, 0);
    }

    function testLtGasBZero() external pure {
        LibDecimalFloat.compare(1, 0, 0, 0);
    }

    function testLtGasBothZero() external pure {
        LibDecimalFloat.compare(0, 0, 0, 0);
    }

    function testLtGasExponentDiffOverflow() external pure {
        LibDecimalFloat.compare(1, type(int256).max, 1, type(int256).min);
    }
}
