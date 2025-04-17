// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

import {LibDecimalFloatSlow} from "test/lib/LibDecimalFloatSlow.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatEqTest is Test {
    using LibDecimalFloat for Float;

    function eqExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (bool)
    {
        return LibDecimalFloat.eq(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    function eqExternal(Float floatA, Float floatB) external pure returns (bool) {
        return LibDecimalFloat.eq(floatA, floatB);
    }

    function testEqPacked(Float a, Float b) external {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        try this.eqExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB) returns (bool eq) {
            bool actual = this.eqExternal(a, b);
            assertEq(eq, actual);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.eqExternal(a, b);
        }
    }

    function testEqReference(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
    {
        bool actual = LibDecimalFloat.eq(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        bool expected = LibDecimalFloatSlow.eqSlow(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        assertEq(actual, expected);
    }

    function testEqNotReverts(int256 x, int256 exponentX, int256 y, int256 exponentY) external pure {
        LibDecimalFloat.eq(x, exponentX, y, exponentY);
    }

    /// x == x
    function testEqX(int256 x) external pure {
        bool eq = LibDecimalFloat.eq(x, 0, x, 0);
        assertTrue(eq);
    }

    /// xeX == xeX
    function testEqOneEAny(int256 x, int256 exponent) external pure {
        bool eq = LibDecimalFloat.eq(x, exponent, x, exponent);
        assertTrue(eq);
    }

    /// xeX != xeY if X != Y && x != 0
    function testEqXEAnyVsXEAny(int256 x, int256 exponentX, int256 exponentY) external pure {
        vm.assume(x != 0);
        bool eq = LibDecimalFloat.eq(x, exponentX, x, exponentY);

        assertEq(eq, exponentX == exponentY);

        // Reverse the order.
        eq = LibDecimalFloat.eq(x, exponentY, x, exponentX);
        assertEq(eq, exponentX == exponentY);
    }

    /// xeX == xeY if x == 0
    function testEqZero(int256 exponentX, int256 exponentY) external pure {
        bool eq = LibDecimalFloat.eq(0, exponentX, 0, exponentY);
        assertTrue(eq);
    }

    /// xeX != yeY if x != y
    function testEqXNotY(int256 x, int256 exponentX, int256 y, int256 exponentY) external pure {
        vm.assume(x != y);
        bool eq = LibDecimalFloat.eq(x, exponentX, y, exponentY);
        assertTrue(!eq);
    }

    /// xeX != yeY if xeX < xeY || xeX > xeY
    function testEqXNotYExponents(int256 x, int256 exponentX, int256 y, int256 exponentY) external pure {
        bool eq = LibDecimalFloat.eq(x, exponentX, y, exponentY);
        bool lt = LibDecimalFloat.lt(x, exponentX, y, exponentY);
        bool gt = LibDecimalFloat.gt(x, exponentX, y, exponentY);

        assertEq(eq, !lt && !gt);
    }

    /// if xeX == yeY, then x / y == 10^(X - Y) || y / x == 10^(Y - X)
    function testEqXEqY(int256 x, int256 exponentX, int256 y, int256 exponentY) external pure {
        bool eq = LibDecimalFloat.eq(x, exponentX, y, exponentY);

        if (eq) {
            if (x == y) {
                assertTrue(exponentX == exponentY || x == 0);
            } else if (y > x) {
                assertTrue(exponentY < exponentX, "y > x but exponentY >= exponentX");
                assertTrue(exponentX - exponentY < 77, "y > x but exponentX - exponentY >= 77");
                assertEq(x / y, int256(10 ** uint256(exponentX - exponentY)), "y > x but x / y != 10^(X - Y)");
                assertEq(x % y, 0, "y > x but x % y != 0");
            } else {
                assertTrue(exponentX < exponentY, "x < y but exponentX >= exponentY");
                assertTrue(exponentY - exponentX < 77, "x < y but exponentY - exponentX >= 77");
                assertEq(y / x, int256(10 ** uint256(exponentY - exponentX)), "x < y but y / x != 10^(Y - X)");
                assertEq(y % x, 0, "x < y but y % x != 0");
            }
        } else {
            if (x == y) {
                assertTrue(exponentX != exponentY);
            }
        }
    }

    function testEqGasDifferentSigns() external pure {
        LibDecimalFloat.eq(1, 0, -1, 0);
    }

    function testEqGasAZero() external pure {
        LibDecimalFloat.eq(0, 0, 1, 0);
    }

    function testEqGasBZero() external pure {
        LibDecimalFloat.eq(1, 0, 0, 0);
    }

    function testEqGasBothZero() external pure {
        LibDecimalFloat.eq(0, 0, 0, 0);
    }

    function testEqGasExponentDiffOverflow() external pure {
        LibDecimalFloat.eq(1, type(int256).max, 1, type(int256).min);
    }
}
