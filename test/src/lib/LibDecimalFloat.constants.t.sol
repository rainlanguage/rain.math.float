// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";

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

    function testFloatMinPositiveValueIsMin(Float a) external pure {
        vm.assume(!a.isZero());
        // cant abs smallest negative value because of overflow.
        vm.assume(a.gt(LibDecimalFloat.FLOAT_MIN_NEGATIVE_VALUE));
        a = a.abs();

        assertTrue(a.gte(LibDecimalFloat.FLOAT_MIN_POSITIVE_VALUE));
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

    function testFloatZero() external pure {
        Float zero = LibDecimalFloat.FLOAT_ZERO;
        Float expected = LibDecimalFloat.packLossless(0, 0);
        assertEq(Float.unwrap(zero), Float.unwrap(expected));
    }

    function testFloatOne() external pure {
        Float one = LibDecimalFloat.FLOAT_ONE;
        Float expected = LibDecimalFloat.packLossless(1, 0);
        assertEq(Float.unwrap(one), Float.unwrap(expected));
    }
}
