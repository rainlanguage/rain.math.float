// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

import {Test} from "forge-std-1.17.0/src/Test.sol";

contract LibDecimalFloatMinusTest is Test {
    using LibDecimalFloat for Float;

    /// a < b iff -a > -b for all non-equal packed floats, but for an
    /// int224.min coefficient and int224.min + 1 at the same exponent, which
    /// both negate to int224.max there (#326).
    function checkNegationReversesOrder(Float a, Float b) internal pure {
        vm.assume(!a.eq(b));
        Float negA = a.minus();
        Float negB = b.minus();
        if (negA.eq(negB)) {
            (int256 signedCoefficientA, int256 exponentA) = a.unpack();
            (int256 signedCoefficientB, int256 exponentB) = b.unpack();
            assertEq(exponentA, exponentB, "collision exponents");
            assertEq(signedCoefficientA + signedCoefficientB, int256(type(int224).min) * 2 + 1, "collision sum");
            assertTrue(
                signedCoefficientA == type(int224).min || signedCoefficientB == type(int224).min, "collision operand"
            );
        } else {
            assertTrue(a.lt(b) == negA.gt(negB), "negation should reverse ordering");
        }
    }

    function testNegationReversesOrder(Float a, Float b) external pure {
        checkNegationReversesOrder(a, b);
    }

    /// The #326 counterexample, both ways round.
    function testNegationReversesOrderInt224Min() external pure {
        Float a = Float.wrap(0x0000000080000000000000000000000000000000000000000000000000000001);
        Float b = Float.wrap(0x0000000080000000000000000000000000000000000000000000000000000000);
        checkNegationReversesOrder(a, b);
        checkNegationReversesOrder(b, a);
        assertEq(Float.unwrap(a.minus()), Float.unwrap(b.minus()));
    }

    /// Every coefficient but int224.min negates exactly at the same exponent.
    function testMinusPacked(Float float) external pure {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        int256 expectedCoefficient =
            signedCoefficient == type(int224).min ? int256(type(int224).max) : -signedCoefficient;
        int256 expectedExponent = signedCoefficient == 0 ? int256(0) : exponent;
        (int256 signedCoefficientMinus, int256 exponentMinus) = float.minus().unpack();
        assertEq(signedCoefficientMinus, expectedCoefficient);
        assertEq(exponentMinus, expectedExponent);
    }

    /// Zero at any exponent negates to `FLOAT_ZERO`.
    function testMinusZero(uint32 exponent) external pure {
        Float zero = Float.wrap(bytes32(uint256(exponent) << 224));
        assertEq(Float.unwrap(zero.minus()), Float.unwrap(LibDecimalFloat.FLOAT_ZERO));
    }

    function checkMinusInt224Min(int256 exponent) internal pure {
        Float result = LibDecimalFloat.packLossless(type(int224).min, exponent).minus();
        (int256 signedCoefficient, int256 resultExponent) = result.unpack();
        assertEq(signedCoefficient, type(int224).max);
        assertEq(resultExponent, exponent);
    }

    /// An int224.min coefficient negates to int224.max at the same exponent.
    function testMinusInt224Min() external pure {
        checkMinusInt224Min(type(int32).min);
        checkMinusInt224Min(-18);
        checkMinusInt224Min(-1);
        checkMinusInt224Min(0);
        checkMinusInt224Min(1);
        checkMinusInt224Min(18);
        checkMinusInt224Min(type(int32).max);
    }

    /// Negating int224.max gives int224.min + 1, not int224.min.
    function testMinusInt224Max() external pure {
        Float result = LibDecimalFloat.packLossless(type(int224).max, 7).minus();
        (int256 signedCoefficient, int256 exponent) = result.unpack();
        assertEq(signedCoefficient, type(int224).min + 1);
        assertEq(exponent, 7);
    }
}
