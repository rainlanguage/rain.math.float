// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatConstantsTest is Test {
    using LibDecimalFloat for Float;

    function testFloatMaxValue() external pure {
        Float maxValue = LibDecimalFloat.FLOAT_MAX_VALUE;
        Float expected = LibDecimalFloat.packLossless(type(int224).max, type(int32).max);
        assertEq(Float.unwrap(maxValue), Float.unwrap(expected));
    }

    function testFloatMinValue() external pure {
        Float minValue = LibDecimalFloat.FLOAT_MIN_NEGATIVE_VALUE;
        Float expected = LibDecimalFloat.packLossless(type(int224).min, type(int32).max);
        assertEq(Float.unwrap(minValue), Float.unwrap(expected));
    }

    function testFloatE() external pure {
        Float e = LibDecimalFloat.FLOAT_E;
        Float expected = LibDecimalFloat.packLossless(
            int224(2.718281828459045235360287471352662497757247093699959574966967627724e66), -66
        );
        assertEq(Float.unwrap(e), Float.unwrap(expected));
    }
}
