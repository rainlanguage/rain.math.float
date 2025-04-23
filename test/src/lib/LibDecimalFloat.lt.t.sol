// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

import {LibDecimalFloatSlow} from "test/lib/LibDecimalFloatSlow.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatLtTest is Test {
    using LibDecimalFloat for Float;

    function testLtReference(Float a, Float b) external pure {
        bool actual = LibDecimalFloat.lt(a, b);
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        bool expected = LibDecimalFloatSlow.ltSlow(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        assertEq(actual, expected);
    }

    /// x !< x
    function testLtX(int224 x) external pure {
        Float a = LibDecimalFloat.packLossless(x, 0);
        bool lt = LibDecimalFloat.lt(a, a);
        assertTrue(!lt);
    }

    /// xeX !< xeX
    function testLtOneEAny(int224 x, int32 exponent) external pure {
        Float a = LibDecimalFloat.packLossless(x, exponent);
        bool lt = LibDecimalFloat.lt(a, a);
        assertTrue(!lt);
    }

    /// xeX < xeY if X < Y && x > 0
    function testLtXEAnyVsXEAny(int256 x, int32 exponentA, int32 exponentB) external pure {
        x = bound(x, 1, type(int224).max);

        Float a = LibDecimalFloat.packLossless(x, exponentA);
        Float b = LibDecimalFloat.packLossless(x, exponentB);

        // Compare the two floats.
        bool lt = a.lt(b);

        assertEq(lt, exponentA < exponentB);

        // Reverse the order.
        lt = b.lt(a);
        assertEq(lt, exponentB < exponentA);
    }

    /// xeX < xeY if X > Y && x < 0
    function testLtXEAnyVsXEAnyNegative(int256 x, int32 exponentA, int32 exponentB) external pure {
        x = bound(x, type(int224).min, -1);
        Float a = LibDecimalFloat.packLossless(x, exponentA);
        Float b = LibDecimalFloat.packLossless(x, exponentB);
        // Compare the two floats.
        bool lt = a.lt(b);

        assertEq(lt, exponentA > exponentB);

        // Reverse the order.
        lt = b.lt(a);
        assertEq(lt, exponentB > exponentA);
    }

    /// xeX !< xeY if x == 0
    function testLtZero(int32 exponentA, int32 exponentB) external pure {
        Float a = LibDecimalFloat.packLossless(0, exponentA);
        Float b = LibDecimalFloat.packLossless(0, exponentB);
        // Compare the two floats.
        bool lt = a.lt(b);
        assertTrue(!lt);
    }

    /// xeX < yeY if x < 0 && y >= 0
    function testLtNegativeVsPositive(
        int256 signedCoefficientNeg,
        int32 exponentNeg,
        int256 signedCoefficientPos,
        int32 exponentPos
    ) external pure {
        signedCoefficientNeg = bound(signedCoefficientNeg, type(int224).min, -1);
        signedCoefficientPos = bound(signedCoefficientPos, 0, type(int224).max);

        Float a = LibDecimalFloat.packLossless(signedCoefficientNeg, exponentNeg);
        Float b = LibDecimalFloat.packLossless(signedCoefficientPos, exponentPos);
        // Compare the two floats.
        bool lt = a.lt(b);
        assertTrue(lt);

        // Reverse the order.
        lt = b.lt(a);
        assertTrue(!lt);
    }

    /// X < Y if Y !< X && X != Y
    function testLtVsEqualVsGt(Float a, Float b) external pure {
        bool lt = a.lt(b);
        bool equal = a.eq(b);
        bool gt = a.gt(b);

        assertEq(lt, !equal && !gt);
    }

    /// X < Y if X < 0 && Y == 0
    function testLtNegativeVsZero(int256 signedCoefficientNeg, int32 exponentNeg, int32 exponentZero) external pure {
        signedCoefficientNeg = bound(signedCoefficientNeg, type(int224).min, -1);
        Float a = LibDecimalFloat.packLossless(signedCoefficientNeg, exponentNeg);
        Float b = LibDecimalFloat.packLossless(0, exponentZero);
        // Compare the two floats.
        bool lt = LibDecimalFloat.lt(a, b);
        assertTrue(lt);

        // Reverse the order.
        lt = LibDecimalFloat.lt(b, a);
        assertTrue(!lt);
    }

    function testLtGasDifferentSigns() external pure {
        LibDecimalFloat.lt(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(-1, 0));
    }

    function testLtGasAZero() external pure {
        LibDecimalFloat.lt(LibDecimalFloat.packLossless(0, 0), LibDecimalFloat.packLossless(1, 0));
    }

    function testLtGasBZero() external pure {
        LibDecimalFloat.lt(LibDecimalFloat.packLossless(1, 0), LibDecimalFloat.packLossless(0, 0));
    }

    function testLtGasBothZero() external pure {
        LibDecimalFloat.lt(LibDecimalFloat.packLossless(0, 0), LibDecimalFloat.packLossless(0, 0));
    }

    function testLtGasExponentDiffOverflow() external pure {
        LibDecimalFloat.lt(
            LibDecimalFloat.packLossless(1, type(int32).max), LibDecimalFloat.packLossless(1, type(int32).min)
        );
    }
}
