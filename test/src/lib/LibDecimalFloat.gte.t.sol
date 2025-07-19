// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

import {LibDecimalFloatSlow} from "test/lib/LibDecimalFloatSlow.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatGteTest is Test {
    using LibDecimalFloat for Float;

    function testGteReference(int224 signedCoefficientA, int32 exponentA, int224 signedCoefficientB, int32 exponentB)
        external
        pure
    {
        Float a = LibDecimalFloat.packLossless(signedCoefficientA, exponentA);
        Float b = LibDecimalFloat.packLossless(signedCoefficientB, exponentB);
        bool actual = a.gte(b);
        bool expected = LibDecimalFloatSlow.gteSlow(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        assertEq(actual, expected);
    }

    /// x >= x
    function testGteX(int224 x, int32 exponent) external pure {
        Float a = LibDecimalFloat.packLossless(x, exponent);
        bool gte = a.gte(a);
        assertTrue(gte);
    }

    /// xeX >= xeX
    function testGteOneEAny(Float a) external pure {
        bool gte = a.gte(a);
        assertTrue(gte);
    }

    /// xeX >= xeY if X >= Y && x > 0
    function testGteXEAnyVsXEAny(int256 x, int32 exponentA, int32 exponentB) external pure {
        x = bound(x, 1, type(int224).max);
        Float a = LibDecimalFloat.packLossless(x, exponentA);
        Float b = LibDecimalFloat.packLossless(x, exponentB);
        bool gte = a.gte(b);

        assertEq(gte, exponentA >= exponentB);

        // Reverse the order.
        gte = b.gte(a);
        assertEq(gte, exponentB >= exponentA);
    }

    /// xeX >= xeY if X <= Y && x < 0
    function testGteXEAnyVsXEAnyNegative(int256 x, int32 exponentA, int32 exponentB) external pure {
        x = bound(x, type(int224).min, -1);
        Float a = LibDecimalFloat.packLossless(x, exponentA);
        Float b = LibDecimalFloat.packLossless(x, exponentB);
        bool gte = a.gte(b);

        assertEq(gte, exponentA <= exponentB);

        // Reverse the order.
        gte = b.gte(a);
        assertEq(gte, exponentB <= exponentA);
    }

    /// xeX >= xeY if x == 0
    function testGteZero(int32 exponentA, int32 exponentB) external pure {
        Float a = LibDecimalFloat.packLossless(0, exponentA);
        Float b = LibDecimalFloat.packLossless(0, exponentB);
        bool gte = a.gte(b);
        assertTrue(gte);
        // Reverse the order.
        gte = b.gte(a);
        assertTrue(gte);
    }

    /// xeX >= yeY if x >= 0 && y < 0
    function testGteXPositiveYNegative(int256 x, int32 exponentX, int256 y, int32 exponentY) external pure {
        x = bound(x, 0, type(int224).max);
        y = bound(y, type(int224).min, -1);
        Float a = LibDecimalFloat.packLossless(x, exponentX);
        Float b = LibDecimalFloat.packLossless(y, exponentY);
        bool gte = a.gte(b);
        assertTrue(gte);

        // Reverse the order.
        gte = b.gte(a);
        assertTrue(!gte);
    }

    /// xeX >= yeY if xeX !< yeY
    function testGteXNotLtY(Float a, Float b) external pure {
        bool gte = a.gte(b);
        bool lt = a.lt(b);

        assertEq(gte, !lt);
    }

    /// xeX >= yeY if xeX >= 0 && yeY == 0
    function testGteXPositiveYZero(int256 x, int32 exponentX, int32 exponentZero) external pure {
        x = bound(x, 0, type(int224).max);
        Float a = LibDecimalFloat.packLossless(x, exponentX);
        Float b = LibDecimalFloat.packLossless(0, exponentZero);
        bool gte = a.gte(b);
        assertTrue(gte);
    }

    function testGteGasDifferentSigns() external pure {
        Float a = LibDecimalFloat.packLossless(1, 0);
        Float b = LibDecimalFloat.packLossless(-1, 0);
        a.gte(b);
    }

    function testGteGasAZero() external pure {
        Float a = LibDecimalFloat.packLossless(0, 0);
        Float b = LibDecimalFloat.packLossless(1, 0);
        a.gte(b);
    }

    function testGteGasBZero() external pure {
        Float a = LibDecimalFloat.packLossless(1, 0);
        Float b = LibDecimalFloat.packLossless(0, 0);
        a.gte(b);
    }

    function testGteGasBothZero() external pure {
        Float a = LibDecimalFloat.packLossless(0, 0);
        a.gte(a);
    }

    function testGteGasExponentDiffOverflow() external pure {
        Float a = LibDecimalFloat.packLossless(1, type(int32).max);
        Float b = LibDecimalFloat.packLossless(1, type(int32).min);
        a.gte(b);
    }
}
