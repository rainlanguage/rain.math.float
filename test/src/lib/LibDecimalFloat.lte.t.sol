// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

import {LibDecimalFloatSlow} from "test/lib/LibDecimalFloatSlow.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatLteTest is Test {
    using LibDecimalFloat for Float;

    function testLteReference(int224 signedCoefficientA, int32 exponentA, int224 signedCoefficientB, int32 exponentB)
        external
        pure
    {
        Float a = LibDecimalFloat.packLossless(signedCoefficientA, exponentA);
        Float b = LibDecimalFloat.packLossless(signedCoefficientB, exponentB);
        bool actual = a.lte(b);
        bool expected = LibDecimalFloatSlow.lteSlow(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        assertEq(actual, expected);
    }

    /// x <= x
    function testLteX(int224 x, int32 exponent) external pure {
        Float a = LibDecimalFloat.packLossless(x, exponent);
        bool lte = a.lte(a);
        assertTrue(lte);
    }

    /// xeX <= xeX
    function testLteOneEAny(Float a) external pure {
        bool lte = a.lte(a);
        assertTrue(lte);
    }

    /// xeX <= xeY if X >= Y && x > 0
    function testLteXEAnyVsXEAny(int256 x, int32 exponentA, int32 exponentB) external pure {
        x = bound(x, 1, type(int224).max);
        Float a = LibDecimalFloat.packLossless(x, exponentA);
        Float b = LibDecimalFloat.packLossless(x, exponentB);
        bool lte = a.lte(b);

        assertEq(lte, exponentA <= exponentB);

        // Reverse the order.
        lte = b.lte(a);
        assertEq(lte, exponentB <= exponentA);
    }

    /// xeX <= xeY if X >= Y && x < 0
    function testLteXEAnyVsXEAnyNegative(int256 x, int32 exponentA, int32 exponentB) external pure {
        x = bound(x, type(int224).min, -1);
        Float a = LibDecimalFloat.packLossless(x, exponentA);
        Float b = LibDecimalFloat.packLossless(x, exponentB);
        bool lte = a.lte(b);

        assertEq(lte, exponentA >= exponentB);

        // Reverse the order.
        lte = b.lte(a);
        assertEq(lte, exponentB >= exponentA);
    }

    /// xeX <= xeY if x == 0
    function testLteZero(int32 exponentA, int32 exponentB) external pure {
        Float a = LibDecimalFloat.packLossless(0, exponentA);
        Float b = LibDecimalFloat.packLossless(0, exponentB);
        bool lte = a.lte(b);
        assertTrue(lte);
        // Reverse the order.
        lte = b.lte(a);
        assertTrue(lte);
    }

    /// yeY <= xeX if x >= 0 && y < 0
    function testLteXPositiveYNegative(int256 x, int32 exponentX, int256 y, int32 exponentY) external pure {
        x = bound(x, 0, type(int224).max);
        y = bound(y, type(int224).min, -1);
        Float a = LibDecimalFloat.packLossless(x, exponentX);
        Float b = LibDecimalFloat.packLossless(y, exponentY);

        bool lte = b.lte(a);
        assertTrue(lte);
    }

    /// xeX <= yeY if xeX !> yeY
    function testLteXNotLtY(Float a, Float b) external pure {
        bool lte = a.lte(b);
        bool gt = a.gt(b);

        assertEq(lte, !gt);
    }

    /// yeY >= xeX if xeX >= 0 && yeY == 0
    function testLteXPositiveYZero(int256 x, int32 exponentX, int32 exponentZero) external pure {
        x = bound(x, 0, type(int224).max);
        Float a = LibDecimalFloat.packLossless(x, exponentX);
        Float b = LibDecimalFloat.packLossless(0, exponentZero);
        bool lte = b.lte(a);
        assertTrue(lte);
    }

    function testLteGasDifferentSigns() external pure {
        Float a = LibDecimalFloat.packLossless(1, 0);
        Float b = LibDecimalFloat.packLossless(-1, 0);
        a.lte(b);
    }

    function testLteGasAZero() external pure {
        Float a = LibDecimalFloat.packLossless(0, 0);
        Float b = LibDecimalFloat.packLossless(1, 0);
        a.lte(b);
    }

    function testLteGasBZero() external pure {
        Float a = LibDecimalFloat.packLossless(1, 0);
        Float b = LibDecimalFloat.packLossless(0, 0);
        a.lte(b);
    }

    function testLteGasBothZero() external pure {
        Float a = LibDecimalFloat.packLossless(0, 0);
        a.lte(a);
    }

    function testLteGasExponentDiffOverflow() external pure {
        Float a = LibDecimalFloat.packLossless(1, type(int32).max);
        Float b = LibDecimalFloat.packLossless(1, type(int32).min);
        a.lte(b);
    }
}
