// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatFracTest is Test {
    using LibDecimalFloat for Float;

    function testFracNotReverts(Float x) external pure {
        x.frac();
    }

    function checkFrac(int256 x, int256 exponent, int256 expectedFrac, int256 expectedFracExponent) internal pure {
        Float a = LibDecimalFloat.packLossless(x, exponent);
        (int256 actualFrac, int256 actualFracExponent) = a.frac().unpack();
        assertEq(actualFrac, expectedFrac);
        assertEq(actualFracExponent, expectedFracExponent);
    }

    /// Every non negative exponent has no fractional component.
    function testFracNonNegative(int224 x, int256 exponent) external pure {
        exponent = bound(exponent, 0, type(int32).max);
        checkFrac(x, exponent, 0, 0);
    }

    /// If the exponent is less than -76 then the fractional component is the
    /// same as the input.
    function testFracLessThanMin(int224 x, int256 exponent) external pure {
        exponent = bound(exponent, type(int32).min, -77);
        checkFrac(x, exponent, x, x == 0 ? int256(0) : exponent);
    }

    /// For exponents [-76,-1] the fractional component is the modulo of 1.
    function testFracInRange(int224 x, int256 exponent) external pure {
        exponent = bound(exponent, -76, -1);
        // exponent [-76, -1]
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 y = x % int256(10 ** uint256(-exponent));
        checkFrac(x, exponent, y, y == 0 ? int256(0) : exponent);
    }

    /// Examples
    function testFracExamples() external pure {
        checkFrac(123456789, 0, 0, 0);
        checkFrac(123456789, -1, 9, -1);
        checkFrac(123456789, -2, 89, -2);
        checkFrac(123456789, -3, 789, -3);
        checkFrac(123456789, -4, 6789, -4);
        checkFrac(123456789, -5, 56789, -5);
        checkFrac(123456789, -6, 456789, -6);
        checkFrac(123456789, -7, 3456789, -7);
        checkFrac(123456789, -8, 23456789, -8);
        checkFrac(123456789, -9, 123456789, -9);
        checkFrac(123456789, -10, 123456789, -10);
        checkFrac(123456789, -11, 123456789, -11);
        checkFrac(2.5e37, -37, 0.5e37, -37);

        // type(int224.max) is 13479973333575319897333507543509815336818572211270286240551805124607
        checkFrac(type(int224).max, 0, 0, 0);
        checkFrac(type(int224).min, 0, 0, 0);
        checkFrac(type(int224).max, 0, 0, 0);
        checkFrac(type(int224).max, -1, 7, -1);
        checkFrac(type(int224).max, -2, 7, -2);
        checkFrac(type(int224).max, -3, 607, -3);
        checkFrac(type(int224).max, -4, 4607, -4);
        checkFrac(type(int224).max, -77, type(int224).max, -77);
        checkFrac(type(int224).max, -78, type(int224).max, -78);
        checkFrac(type(int224).max, -76, 13479973333575319897333507543509815336818572211270286240551805124607, -76);
    }

    function testFracGasZero() external pure {
        Float a = LibDecimalFloat.packLossless(0, 0);
        a.frac();
    }

    function testFracGasTiny() external pure {
        Float a = LibDecimalFloat.packLossless(1, -100);
        a.frac();
    }

    function testFracGas0() external pure {
        Float a = LibDecimalFloat.packLossless(2.5e37, -37);
        a.frac();
    }
}
