// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

import {LibDecimalFloatSlow} from "test/lib/LibDecimalFloatSlow.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatLtTest is Test {
    using LibDecimalFloat for Float;

    function ltExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (bool)
    {
        return LibDecimalFloat.lt(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    function ltExternal(Float memory floatA, Float memory floatB) external pure returns (bool) {
        return LibDecimalFloat.lt(floatA, floatB);
    }
    /// Test to verify that stack-based and memory-based implementations produce the same results.

    function testLtMem(Float memory a, Float memory b) external {
        try this.ltExternal(a.signedCoefficient, a.exponent, b.signedCoefficient, b.exponent) returns (bool lt) {
            bool actual = this.ltExternal(a, b);
            assertEq(lt, actual);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.ltExternal(a, b);
        }
    }

    function testLtReference(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
    {
        bool actual = LibDecimalFloat.lt(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        bool expected = LibDecimalFloatSlow.ltSlow(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        assertEq(actual, expected);
    }

    /// x !< x
    function testLtX(int256 x) external pure {
        bool lt = LibDecimalFloat.lt(x, 0, x, 0);
        assertTrue(!lt);
    }

    /// xeX !< xeX
    function testLtOneEAny(int256 x, int256 exponent) external pure {
        bool lt = LibDecimalFloat.lt(x, exponent, x, exponent);
        assertTrue(!lt);
    }

    /// xeX < xeY if X < Y && x > 0
    function testLtXEAnyVsXEAny(int256 x, int256 exponentA, int256 exponentB) external pure {
        x = bound(x, 1, type(int256).max);
        bool lt = LibDecimalFloat.lt(x, exponentA, x, exponentB);

        assertEq(lt, exponentA < exponentB);

        // Reverse the order.
        lt = LibDecimalFloat.lt(x, exponentB, x, exponentA);
        assertEq(lt, exponentB < exponentA);
    }

    /// xeX < xeY if X > Y && x < 0
    function testLtXEAnyVsXEAnyNegative(int256 x, int256 exponentA, int256 exponentB) external pure {
        x = bound(x, type(int256).min, -1);
        bool lt = LibDecimalFloat.lt(x, exponentA, x, exponentB);

        assertEq(lt, exponentA > exponentB);

        // Reverse the order.
        lt = LibDecimalFloat.lt(x, exponentB, x, exponentA);
        assertEq(lt, exponentB > exponentA);
    }

    /// xeX !< xeY if x == 0
    function testLtZero(int256 exponentA, int256 exponentB) external pure {
        bool lt = LibDecimalFloat.lt(0, exponentA, 0, exponentB);
        assertTrue(!lt);
    }

    /// xeX < yeY if x < 0 && y >= 0
    function testLtNegativeVsPositive(
        int256 signedCoefficientNeg,
        int256 exponentNeg,
        int256 signedCoefficientPos,
        int256 exponentPos
    ) external pure {
        signedCoefficientNeg = bound(signedCoefficientNeg, type(int256).min, -1);
        signedCoefficientPos = bound(signedCoefficientPos, 0, type(int256).max);

        bool lt = LibDecimalFloat.lt(signedCoefficientNeg, exponentNeg, signedCoefficientPos, exponentPos);
        assertTrue(lt);

        // Reverse the order.
        lt = LibDecimalFloat.lt(signedCoefficientPos, exponentPos, signedCoefficientNeg, exponentNeg);
        assertTrue(!lt);
    }

    /// X < Y if Y !< X && X != Y
    function testLtVsEqualVsGt(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
    {
        bool lt = LibDecimalFloat.lt(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        bool equal = LibDecimalFloat.eq(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        bool gt = LibDecimalFloat.gt(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        assertEq(lt, !equal && !gt);
    }

    /// X < Y if X < 0 && Y == 0
    function testLtNegativeVsZero(int256 signedCoefficientNeg, int256 exponentNeg, int256 exponentZero) external pure {
        signedCoefficientNeg = bound(signedCoefficientNeg, type(int256).min, -1);

        bool lt = LibDecimalFloat.lt(signedCoefficientNeg, exponentNeg, 0, exponentZero);
        assertTrue(lt);

        // Reverse the order.
        lt = LibDecimalFloat.lt(0, exponentZero, signedCoefficientNeg, exponentNeg);
        assertTrue(!lt);
    }

    function testLtGasDifferentSigns() external pure {
        LibDecimalFloat.lt(1, 0, -1, 0);
    }

    function testLtGasAZero() external pure {
        LibDecimalFloat.lt(0, 0, 1, 0);
    }

    function testLtGasBZero() external pure {
        LibDecimalFloat.lt(1, 0, 0, 0);
    }

    function testLtGasBothZero() external pure {
        LibDecimalFloat.lt(0, 0, 0, 0);
    }

    function testLtGasExponentDiffOverflow() external pure {
        LibDecimalFloat.lt(1, type(int256).max, 1, type(int256).min);
    }
}
