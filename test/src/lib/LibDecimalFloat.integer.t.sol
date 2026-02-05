// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatIntegerTest is Test {
    using LibDecimalFloat for Float;

    function testIntegerNotReverts(Float x) external pure {
        x.integer();
    }

    function checkInteger(int256 x, int256 exponent, int256 expectedInteger, int256 expectedIntegerExponent)
        internal
        pure
    {
        Float a = LibDecimalFloat.packLossless(x, exponent);
        (int256 actualInteger, int256 actualIntegerExponent) = a.integer().unpack();
        assertEq(actualInteger, expectedInteger);
        assertEq(actualIntegerExponent, expectedIntegerExponent);
    }

    /// Every non negative exponent has the entire number as the integer component.
    function testIntegerNonNegative(int224 x, int256 exponent) external pure {
        exponent = bound(exponent, 0, type(int32).max);
        checkInteger(x, exponent, x, x == 0 ? int256(0) : exponent);
    }

    /// If the exponent is less than -76 then the integer component is zero.
    function testIntegerLessThanMin(int224 x, int256 exponent) external pure {
        exponent = bound(exponent, type(int32).min, -77);
        checkInteger(x, exponent, 0, 0);
    }

    /// For exponents [-76,-1] the integer component is the input minus the
    /// modulo of 1.
    function testIntegerInRange(int224 x, int256 exponent) external pure {
        exponent = bound(exponent, -76, -1);
        // exponent [-76, -1]
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 y = x - (x % int256(10 ** uint256(-exponent)));
        checkInteger(x, exponent, y, y == 0 ? int256(0) : exponent);
    }

    /// Examples
    function testIntegerExamples() external pure {
        checkInteger(123456789, 0, 123456789, 0);
        checkInteger(123456789, -1, 123456780, -1);
        checkInteger(123456789, -2, 123456700, -2);
        checkInteger(123456789, -3, 123456000, -3);
        checkInteger(123456789, -4, 123450000, -4);
        checkInteger(123456789, -5, 123400000, -5);
        checkInteger(123456789, -6, 123000000, -6);
        checkInteger(123456789, -7, 120000000, -7);
        checkInteger(123456789, -8, 100000000, -8);
        checkInteger(123456789, -9, 0, 0);
        checkInteger(123456789, -10, 0, 0);
        checkInteger(123456789, -11, 0, 0);
        checkInteger(2.5e37, -37, 2e37, -37);

        // Negative numbers
        checkInteger(-123456789, 0, -123456789, 0);
        checkInteger(-123456789, -1, -123456780, -1);
        checkInteger(-123456789, -2, -123456700, -2);
        checkInteger(-123456789, -3, -123456000, -3);
        checkInteger(-123456789, -4, -123450000, -4);
        checkInteger(-123456789, -5, -123400000, -5);
        checkInteger(-123456789, -6, -123000000, -6);
        checkInteger(-123456789, -7, -120000000, -7);
        checkInteger(-123456789, -8, -100000000, -8);
        checkInteger(-123456789, -9, 0, 0);
        checkInteger(-123456789, -10, 0, 0);
        checkInteger(-123456789, -11, 0, 0);
        checkInteger(-2.5e37, -37, -2e37, -37);

        // int224 max edge cases
        checkInteger(type(int224).max, 0, type(int224).max, 0);
        checkInteger(type(int224).max, -1, type(int224).max / 10 * 10, -1);
        checkInteger(type(int224).max, -76, 0, 0);

        // int224 min edge cases
        checkInteger(type(int224).min, 0, type(int224).min, 0);
        checkInteger(type(int224).min, -1, type(int224).min / 10 * 10, -1);
        checkInteger(type(int224).min, -76, 0, 0);
    }
}
