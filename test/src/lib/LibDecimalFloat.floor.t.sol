// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatFloorTest is Test {
    using LibDecimalFloat for Float;

    function testFloorNotReverts(Float x) external pure {
        x.floor();
    }

    function checkFloor(int256 x, int256 exponent, int256 expectedFrac, int256 expectedFracExponent) internal pure {
        Float a = LibDecimalFloat.packLossless(x, exponent);
        (x, exponent) = a.floor().unpack();
        assertEq(x, expectedFrac);
        assertEq(exponent, expectedFracExponent);
    }

    function checkFloorEq(int256 x, int256 exponent, int256 expectedFrac, int256 expectedFracExponent) internal pure {
        Float a = LibDecimalFloat.packLossless(x, exponent);
        (x, exponent) = a.floor().unpack();
        assertTrue((LibDecimalFloatImplementation.eq(x, exponent, expectedFrac, expectedFracExponent)));
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
            checkFloor(x, exponent, -1e67, -67);
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
        checkFloor(-123456789, -1, -12345679e60, -60);
        checkFloor(12345678900, -2, 12345678900, -2);

        checkFloor(123456789, -2, 123456700, -2);
        checkFloor(-123456789, -2, -1234568e61, -61);

        checkFloor(123456789, -3, 123456000, -3);
        checkFloor(-123456789, -3, -123457e62, -62);

        checkFloor(123456789, -4, 123450000, -4);
        checkFloor(-123456789, -4, -12346e63, -63);

        checkFloor(123456789, -5, 123400000, -5);
        checkFloor(-123456789, -5, -1235e64, -64);

        checkFloor(123456789, -6, 123000000, -6);
        checkFloor(-123456789, -6, -124e65, -65);

        checkFloor(123456789, -7, 120000000, -7);
        checkFloor(-123456789, -7, -13e66, -66);

        checkFloor(123456789, -8, 100000000, -8);
        checkFloor(-123456789, -8, -2e66, -66);

        checkFloor(123456789, -9, 0, 0);
        checkFloor(-123456789, -9, -1e67, -67);

        checkFloor(123456789, -10, 0, 0);
        checkFloor(-123456789, -10, -1e67, -67);

        checkFloor(123456789, -11, 0, 0);
        checkFloor(-123456789, -11, -1e67, -67);

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
}
