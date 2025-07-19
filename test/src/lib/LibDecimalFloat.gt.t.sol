// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

import {LibDecimalFloatSlow} from "test/lib/LibDecimalFloatSlow.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatGtTest is Test {
    using LibDecimalFloat for Float;

    function testGtReference(int224 signedCoefficientA, int32 exponentA, int224 signedCoefficientB, int32 exponentB)
        external
        pure
    {
        Float a = LibDecimalFloat.packLossless(signedCoefficientA, exponentA);
        Float b = LibDecimalFloat.packLossless(signedCoefficientB, exponentB);
        bool actual = a.gt(b);
        bool expected = LibDecimalFloatSlow.gtSlow(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        assertEq(actual, expected);
    }

    /// x !> x
    function testGtX(int224 x, int32 exponent) external pure {
        Float a = LibDecimalFloat.packLossless(x, exponent);
        bool gt = a.gt(a);
        assertTrue(!gt);
    }

    /// xeX !> xeX
    function testGtOneEAny(Float a) external pure {
        bool gt = a.gt(a);
        assertTrue(!gt);
    }

    /// xeX > xeY if X > Y && x > 0
    function testGtXEAnyVsXEAny(int256 x, int32 exponentA, int32 exponentB) external pure {
        x = bound(x, 1, type(int224).max);
        Float a = LibDecimalFloat.packLossless(x, exponentA);
        Float b = LibDecimalFloat.packLossless(x, exponentB);
        bool gt = a.gt(b);

        assertEq(gt, exponentA > exponentB);

        // Reverse the order.
        gt = b.gt(a);
        assertEq(gt, exponentB > exponentA);
    }

    /// xeX > xeY if X < Y && x < 0
    function testGtXEAnyVsXEAnyNegative(int256 x, int32 exponentA, int32 exponentB) external pure {
        x = bound(x, type(int224).min, -1);
        Float a = LibDecimalFloat.packLossless(x, exponentA);
        Float b = LibDecimalFloat.packLossless(x, exponentB);
        bool gt = a.gt(b);

        assertEq(gt, exponentA < exponentB);

        // Reverse the order.
        gt = b.gt(a);
        assertEq(gt, exponentB < exponentA);
    }

    /// xeX !> xeY if x == 0
    function testGtZero(int32 exponentA, int32 exponentB) external pure {
        Float a = LibDecimalFloat.packLossless(0, exponentA);
        Float b = LibDecimalFloat.packLossless(0, exponentB);
        bool gt = a.gt(b);
        assertTrue(!gt);
        // Reverse the order.
        gt = b.gt(a);
        assertTrue(!gt);
    }

    /// xeX > yeY if x >= 0 && y < 0
    function testGtXPositiveYNegative(int256 x, int32 exponentX, int256 y, int32 exponentY) external pure {
        x = bound(x, 0, type(int224).max);
        y = bound(y, type(int224).min, -1);
        Float a = LibDecimalFloat.packLossless(x, exponentX);
        Float b = LibDecimalFloat.packLossless(y, exponentY);
        bool gt = a.gt(b);
        assertTrue(gt);

        // Reverse the order.
        gt = b.gt(a);
        assertTrue(!gt);
    }

    /// xeX > yeY if xeX != yeY && xeX !< yeY
    function testGtXNotY(Float a, Float b) external pure {
        bool gt = a.gt(b);
        bool eq = a.eq(b);
        bool lt = a.lt(b);

        assertEq(gt, !lt && !eq);
    }

    /// xeX > yeY if xeX > 0 && yeY == 0
    function testGtXPositiveYZero(int256 x, int32 exponentX, int32 exponentZero) external pure {
        x = bound(x, 1, type(int224).max);
        Float a = LibDecimalFloat.packLossless(x, exponentX);
        Float b = LibDecimalFloat.packLossless(0, exponentZero);
        bool gt = a.gt(b);
        assertTrue(gt);

        // Reverse the order.
        gt = b.gt(a);
        assertTrue(!gt);
    }

    function testGtGasDifferentSigns() external pure {
        Float a = LibDecimalFloat.packLossless(1, 0);
        Float b = LibDecimalFloat.packLossless(-1, 0);
        a.gt(b);
    }

    function testGtGasAZero() external pure {
        Float a = LibDecimalFloat.packLossless(0, 0);
        Float b = LibDecimalFloat.packLossless(1, 0);
        a.gt(b);
    }

    function testGtGasBZero() external pure {
        Float a = LibDecimalFloat.packLossless(1, 0);
        Float b = LibDecimalFloat.packLossless(0, 0);
        a.gt(b);
    }

    function testGtGasBothZero() external pure {
        Float a = LibDecimalFloat.packLossless(0, 0);
        a.gt(a);
    }

    function testGtGasExponentDiffOverflow() external pure {
        Float a = LibDecimalFloat.packLossless(1, type(int32).max);
        Float b = LibDecimalFloat.packLossless(1, type(int32).min);
        a.gt(b);
    }
}
