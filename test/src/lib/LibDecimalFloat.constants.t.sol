// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";

contract LibDecimalFloatConstantsTest is Test {
    using LibDecimalFloat for Float;

    function testFloatMaxPositiveValue() external pure {
        Float maxValue = LibDecimalFloat.FLOAT_MAX_POSITIVE_VALUE;
        Float expected = LibDecimalFloat.packLossless(type(int224).max, type(int32).max);
        assertEq(Float.unwrap(maxValue), Float.unwrap(expected));
    }

    function testFloatMaxPositiveValueIsMax(Float a) external pure {
        assertTrue(a.lte(LibDecimalFloat.FLOAT_MAX_POSITIVE_VALUE));
    }

    function testFloatMinPositiveValue() external pure {
        Float minValue = LibDecimalFloat.FLOAT_MIN_POSITIVE_VALUE;
        Float expected = LibDecimalFloat.packLossless(1, type(int32).min);
        assertEq(Float.unwrap(minValue), Float.unwrap(expected));
    }

    /// Every non-zero magnitude is at least the smallest positive value.
    function testFloatMinPositiveValueIsMin(Float a) external pure {
        assertEq(a.abs().gte(LibDecimalFloat.FLOAT_MIN_POSITIVE_VALUE), !a.isZero());
    }

    function testFloatMinNegativeValueAbsIsMaxPositiveValue() external pure {
        assertEq(
            Float.unwrap(LibDecimalFloat.FLOAT_MIN_NEGATIVE_VALUE.abs()),
            Float.unwrap(LibDecimalFloat.FLOAT_MAX_POSITIVE_VALUE)
        );
    }

    function testFloatMaxNegativeValue() external pure {
        Float maxNegativeValue = LibDecimalFloat.FLOAT_MAX_NEGATIVE_VALUE;
        Float expected = LibDecimalFloat.packLossless(-1, type(int32).min);
        assertEq(Float.unwrap(maxNegativeValue), Float.unwrap(expected));
    }

    function testFloatMaxNegativeValueIsMax(Float a) external pure {
        vm.assume(!a.isZero());
        if (a.gt(LibDecimalFloat.FLOAT_ZERO)) {
            a = a.minus();
        }

        assertTrue(a.lte(LibDecimalFloat.FLOAT_MAX_NEGATIVE_VALUE));
    }

    function testFloatMinNegativeValue() external pure {
        Float minValue = LibDecimalFloat.FLOAT_MIN_NEGATIVE_VALUE;
        Float expected = LibDecimalFloat.packLossless(type(int224).min, type(int32).max);
        assertEq(Float.unwrap(minValue), Float.unwrap(expected));
    }

    function testFloatMinNegativeValueIsMin(Float a) external pure {
        assertTrue(a.gte(LibDecimalFloat.FLOAT_MIN_NEGATIVE_VALUE));
    }

    function testFloatE() external pure {
        Float e = LibDecimalFloat.FLOAT_E;
        Float expected = LibDecimalFloat.packLossless(
            int224(2.718281828459045235360287471352662497757247093699959574966967627724e66), -66
        );
        assertEq(Float.unwrap(e), Float.unwrap(expected));
    }

    function testFloatPi() external pure {
        Float pi = LibDecimalFloat.FLOAT_PI;
        Float expected = LibDecimalFloat.packLossless(
            int224(3.141592653589793238462643383279502884197169399375105820974944592307e66), -66
        );
        assertEq(Float.unwrap(pi), Float.unwrap(expected));
    }

    /// The first 72 significant digits of pi, from OEIS A000796
    /// (https://oeis.org/A000796/b000796.txt).
    int256 constant PI_72_DIGITS = 314159265358979323846264338327950288419716939937510582097494459230781640;

    /// The first 72 significant digits of e, from OEIS A001113
    /// (https://oeis.org/A001113/b001113.txt).
    int256 constant E_72_DIGITS = 271828182845904523536028747135266249775724709369995957496696762772407663;

    /// `float` is the closest Float not above `digits72 × 10^-71 + [0, 10^-71)`,
    /// a value in [1, 10), at the finest exponent whose coefficient fits.
    function checkClosestFloatNotAbove(Float float, int256 digits72) internal pure {
        (int256 c, int256 exponent) = LibDecimalFloat.unpack(float);
        assertEq(exponent, -66);
        assertTrue(c > 0);
        // c × 10^-66 <= digits72 × 10^-71 <= value.
        assertTrue(c * 1e5 <= digits72);
        // value < (digits72 + 1) × 10^-71 <= (c + 1) × 10^-66.
        assertTrue((c + 1) * 1e5 >= digits72 + 1);
        // At exponent -67 the coefficient floor(value × 10^67) is
        // floor(digits72 / 10^4), which does not fit in int224.
        assertTrue(digits72 / 1e4 > type(int224).max);
    }

    function testFloatPiIsTheClosestFloatNotAbovePi() external pure {
        checkClosestFloatNotAbove(LibDecimalFloat.FLOAT_PI, PI_72_DIGITS);
    }

    function testFloatEIsTheClosestFloatNotAboveE() external pure {
        checkClosestFloatNotAbove(LibDecimalFloat.FLOAT_E, E_72_DIGITS);
    }

    function testFloatZero() external pure {
        Float zero = LibDecimalFloat.FLOAT_ZERO;
        assertEq(Float.unwrap(zero), bytes32(0));
    }

    function testFloatOne() external pure {
        Float one = LibDecimalFloat.FLOAT_ONE;
        Float expected = LibDecimalFloat.packLossless(1, 0);
        assertEq(Float.unwrap(one), Float.unwrap(expected));
    }

    function testFloatHalf() external pure {
        Float half = LibDecimalFloat.FLOAT_HALF;
        Float expected = LibDecimalFloat.packLossless(5, -1);
        assertEq(Float.unwrap(half), Float.unwrap(expected));
    }

    function testFloatTwo() external pure {
        Float two = LibDecimalFloat.FLOAT_TWO;
        Float expected = LibDecimalFloat.packLossless(2, 0);
        assertEq(Float.unwrap(two), Float.unwrap(expected));
    }
}
