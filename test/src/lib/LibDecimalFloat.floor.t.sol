// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "../../../src/lib/LibDecimalFloat.sol";
import {LibExactFloat} from "../../lib/LibExactFloat.sol";
import {zeroAt} from "../../lib/LibTestFloatZero.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";

contract LibDecimalFloatFloorTest is Test {
    using LibDecimalFloat for Float;

    function checkFloor(int256 x, int256 exponent, int256 expectedFrac, int256 expectedFracExponent) internal pure {
        Float a = LibDecimalFloat.packLossless(x, exponent);
        (x, exponent) = a.floor().unpack();
        assertEq(x, expectedFrac);
        assertEq(exponent, expectedFracExponent);
    }

    function checkFloorEq(int256 x, int256 exponent, int256 expectedFrac, int256 expectedFracExponent) internal pure {
        Float a = LibDecimalFloat.packLossless(x, exponent);
        (x, exponent) = a.floor().unpack();
        assertTrue(LibExactFloat.eq(x, exponent, expectedFrac, expectedFracExponent));
    }

    /// Every non negative exponent is identity for floor.
    function testFloorNonNegative(int224 x, int256 exponent) external pure {
        exponent = bound(exponent, 0, type(int32).max);
        checkFloor(x, exponent, x, x == 0 ? int256(0) : exponent);
    }

    /// If the exponent is less than -76 then the floor is 0 or -1.
    function testFloorLessThanMin(int224 x, int256 exponent) external pure {
        exponent = bound(exponent, type(int32).min, -77);
        if (x >= 0) {
            checkFloor(x, exponent, 0, 0);
        } else {
            checkFloorEq(x, exponent, -1, 0);
        }
    }

    /// For exponents [-76,-1] the floor is the / 1.
    function testFloorInRangeNonNegative(int224 x, int256 exponent) external pure {
        x = int224(bound(int256(x), 0, int256(type(int224).max)));
        exponent = bound(exponent, -76, -1);
        // exponent [-76, -1]
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 scale = int256(10 ** uint256(-exponent));
        // truncation is intentional here.
        // forge-lint: disable-next-line(divide-before-multiply)
        int256 y = (x / scale) * scale;
        checkFloor(x, exponent, y, y == 0 ? int256(0) : exponent);
    }

    /// For exponents [-76,-1] the floor is the / 1 - 1 if the float is negative.
    function testFloorInRangeNegative(int224 x, int256 exponent) external pure {
        x = int224(bound(int256(x), int256(type(int224).min), -1));
        exponent = bound(exponent, -76, -1);
        // exponent [-76, -1]
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 scale = int256(10 ** uint256(-exponent));
        // truncation is intentional here.
        // forge-lint: disable-next-line(divide-before-multiply)
        int256 y = (x / scale) * scale;
        if (y != x) {
            y -= scale;
        }
        checkFloorEq(x, exponent, y, y == 0 ? int256(0) : exponent);
    }

    /// Examples
    function testFloorExamples() external pure {
        checkFloor(123456789, 0, 123456789, 0);
        checkFloor(-123456789, 0, -123456789, 0);
        checkFloor(-1234567890, -1, -1234567890, -1);

        checkFloor(123456789, -1, 123456780, -1);
        checkFloorEq(-123456789, -1, -12345679, 0);
        checkFloor(12345678900, -2, 12345678900, -2);

        checkFloor(123456789, -2, 123456700, -2);
        checkFloorEq(-123456789, -2, -1234568, 0);

        checkFloor(123456789, -3, 123456000, -3);
        checkFloorEq(-123456789, -3, -123457, 0);

        checkFloor(123456789, -4, 123450000, -4);
        checkFloorEq(-123456789, -4, -12346, 0);

        checkFloor(123456789, -5, 123400000, -5);
        checkFloorEq(-123456789, -5, -1235, 0);

        checkFloor(123456789, -6, 123000000, -6);
        checkFloorEq(-123456789, -6, -124, 0);

        checkFloor(123456789, -7, 120000000, -7);
        checkFloorEq(-123456789, -7, -13, 0);

        checkFloor(123456789, -8, 100000000, -8);
        checkFloorEq(-123456789, -8, -2, 0);

        checkFloor(123456789, -9, 0, 0);
        checkFloorEq(-123456789, -9, -1, 0);

        checkFloor(123456789, -10, 0, 0);
        checkFloorEq(-123456789, -10, -1, 0);

        checkFloor(123456789, -11, 0, 0);
        checkFloorEq(-123456789, -11, -1, 0);

        checkFloor(type(int224).max, 0, type(int224).max, 0);
        checkFloor(type(int224).min, 0, type(int224).min, 0);

        checkFloor(2.5e37, -37, 2e37, -37);

        checkFloor(type(int224).max, 0, type(int224).max, 0);
        checkFloor(type(int224).max, -1, 13479973333575319897333507543509815336818572211270286240551805124600, -1);
        checkFloor(type(int224).max, -2, 13479973333575319897333507543509815336818572211270286240551805124600, -2);
        checkFloor(type(int224).max, -3, 13479973333575319897333507543509815336818572211270286240551805124000, -3);
        checkFloor(type(int224).max, -4, 13479973333575319897333507543509815336818572211270286240551805120000, -4);
        checkFloor(type(int224).max, -77, 0, 0);
        checkFloor(type(int224).max, -78, 0, 0);
        checkFloor(type(int224).max, -76, 0, 0);
    }

    function testFloorGasZero() external pure {
        Float a = LibDecimalFloat.packLossless(0, 0);
        a.floor();
    }

    function testFloorGasTiny() external pure {
        Float a = LibDecimalFloat.packLossless(1, -100);
        a.floor();
    }

    function testFloorGas0() external pure {
        Float a = LibDecimalFloat.packLossless(2.5e37, -37);
        a.floor();
    }

    /// `floor` of every Float equals its exact value.
    function testFloorExact(int224 c, int32 e) external pure {
        checkFloorExact(c, e);
    }

    /// Exponents near the decimal point, where the integer and fraction both
    /// carry digits.
    function testFloorExactNearUnit(int224 c, int32 e) external pure {
        checkFloorExact(c, int32(bound(e, -80, 5)));
    }

    function checkFloorExact(int224 c, int32 e) internal pure {
        (int256 rc, int256 re) = LibDecimalFloat.packLossless(c, e).floor().unpack();
        (int256 xc, int256 xe) = LibExactFloat.floorParts(c, e);
        assertEq(LibExactFloat.cmpParts(rc, re, xc, xe), 0, "exact floor");
    }

    /// A zero input of any exponent gives `FLOAT_ZERO`, byte for byte (#687).
    function testFloatFloorZeroBytesExamples() external pure {
        int32[5] memory exponents = [int32(5), type(int32).max, -2, -77, type(int32).min];
        for (uint256 i = 0; i < exponents.length; i++) {
            assertEq(
                Float.unwrap(LibDecimalFloat.floor(zeroAt(exponents[i]))),
                Float.unwrap(LibDecimalFloat.FLOAT_ZERO),
                "floor of zero is not FLOAT_ZERO"
            );
        }
    }

    /// A zero input of any exponent gives `FLOAT_ZERO`, byte for byte (#687).
    function testFloatFloorZeroBytes(int32 e) external pure {
        assertEq(
            Float.unwrap(LibDecimalFloat.floor(zeroAt(e))),
            Float.unwrap(LibDecimalFloat.FLOAT_ZERO),
            "floor of zero is not FLOAT_ZERO"
        );
    }
}
