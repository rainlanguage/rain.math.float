// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat} from "src/lib/LibDecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatGtTest is Test {
    /// x !> x
    function testGtX(int256 x) external pure {
        bool gt = LibDecimalFloat.gt(x, 0, x, 0);
        assertTrue(!gt);
    }

    /// xeX !> xeX
    function testGtOneEAny(int256 x, int256 exponent) external pure {
        bool gt = LibDecimalFloat.gt(x, exponent, x, exponent);
        assertTrue(!gt);
    }

    /// xeX > xeY if X > Y && x > 0
    function testGtXEAnyVsXEAny(int256 x, int256 exponentA, int256 exponentB) external pure {
        x = bound(x, 1, type(int256).max);
        bool gt = LibDecimalFloat.gt(x, exponentA, x, exponentB);

        assertEq(gt, exponentA > exponentB);

        // Reverse the order.
        gt = LibDecimalFloat.gt(x, exponentB, x, exponentA);
        assertEq(gt, exponentB > exponentA);
    }

    /// xeX > xeY if X < Y && x < 0
    function testGtXEAnyVsXEAnyNegative(int256 x, int256 exponentA, int256 exponentB) external pure {
        x = bound(x, type(int256).min, -1);
        bool gt = LibDecimalFloat.gt(x, exponentA, x, exponentB);

        assertEq(gt, exponentA < exponentB);

        // Reverse the order.
        gt = LibDecimalFloat.gt(x, exponentB, x, exponentA);
        assertEq(gt, exponentB < exponentA);
    }

    /// xeX !> xeY if x == 0
    function testGtZero(int256 exponentA, int256 exponentB) external pure {
        bool gt = LibDecimalFloat.gt(0, exponentA, 0, exponentB);
        assertTrue(!gt);
    }

    /// xeX > yeY if xeX != yeY && xeX !< yeY
    function testGtXNotY(int256 x, int256 exponentX, int256 y, int256 exponentY) external pure {
        bool gt = LibDecimalFloat.gt(x, exponentX, y, exponentY);
        bool eq = LibDecimalFloat.eq(x, exponentX, y, exponentY);
        bool lt = LibDecimalFloat.lt(x, exponentX, y, exponentY);

        assertEq(gt, !lt && !eq);
    }

    function testGtGasDifferentSigns() external pure {
        LibDecimalFloat.gt(1, 0, -1, 0);
    }

    function testGtGasAZero() external pure {
        LibDecimalFloat.gt(0, 0, 1, 0);
    }

    function testGtGasBZero() external pure {
        LibDecimalFloat.gt(1, 0, 0, 0);
    }

    function testGtGasBothZero() external pure {
        LibDecimalFloat.gt(0, 0, 0, 0);
    }

    function testGtGasExponentDiffOverflow() external pure {
        LibDecimalFloat.gt(1, type(int256).max, 1, type(int256).min);
    }
}
