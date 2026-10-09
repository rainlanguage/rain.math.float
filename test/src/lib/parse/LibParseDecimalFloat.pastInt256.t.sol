// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {LibParseDecimalFloat} from "src/lib/parse/LibParseDecimalFloat.sol";
import {LibBytes, Pointer} from "rain-solmem-0.1.28/src/lib/LibBytes.sol";
import {Strings} from "@openzeppelin-contracts-5.7.0/utils/Strings.sol";
import {ParseDecimalOverflow} from "rain-string-0.3.9/src/error/ErrParse.sol";
import {
    ParseDecimalPrecisionLoss,
    MalformedDecimalPoint,
    ParseDecimalFloatExcessCharacters
} from "src/error/ErrParse.sol";
import {Float, LibDecimalFloat} from "src/lib/LibDecimalFloat.sol";

contract LibParseDecimalFloatPastInt256Test is Test {
    using LibDecimalFloat for Float;
    using LibBytes for bytes;
    using Strings for uint256;

    string constant INT256_MAX = "57896044618658097711785492504343953926634992332820282019728792003956564819967";
    string constant INT256_MAX_PLUS_ONE =
        "57896044618658097711785492504343953926634992332820282019728792003956564819968";
    string constant INT256_MAX_PLUS_TWO =
        "57896044618658097711785492504343953926634992332820282019728792003956564819969";

    function zeros(uint256 n) internal pure returns (string memory z) {
        z = new string(n);
        for (uint256 i = 0; i < n; i++) {
            bytes(z)[i] = "0";
        }
    }

    function parseInline(string memory data)
        external
        pure
        returns (bytes4 errorSelector, uint256 cursorAfter, int256 signedCoefficient, int256 exponent)
    {
        uint256 start = Pointer.unwrap(bytes(data).dataPointer());
        (errorSelector, cursorAfter, signedCoefficient, exponent) =
            LibParseDecimalFloat.parseDecimalFloatInline(start, Pointer.unwrap(bytes(data).endDataPointer()));
        cursorAfter -= start;
    }

    function parse(string memory data) external pure returns (bytes4 errorSelector, Float float) {
        (errorSelector, float) = LibParseDecimalFloat.parseDecimalFloat(data);
    }

    /// The inline parse and the packed parse both give exactly `c`e`e`.
    function checkExact(string memory s, int256 c, int256 e, int256 packedC, int256 packedE) internal view {
        (bytes4 err, uint256 cursor, int256 inlineC, int256 inlineE) = this.parseInline(s);
        assertEq(err, bytes4(0), "inline error");
        assertEq(cursor, bytes(s).length, "cursor");
        assertEq(inlineC, c, "inline coefficient");
        assertEq(inlineE, e, "inline exponent");
        Float float;
        (err, float) = this.parse(s);
        assertEq(err, bytes4(0), "error");
        (int256 actualC, int256 actualE) = float.unpack();
        assertEq(actualC, packedC, "coefficient");
        assertEq(actualE, packedE, "exponent");
    }

    /// The inline parse gives `c`e`e`, which is no Float.
    function checkLoss(string memory s, int256 c, int256 e) internal view {
        (bytes4 err, uint256 cursor, int256 inlineC, int256 inlineE) = this.parseInline(s);
        assertEq(err, bytes4(0), "inline error");
        assertEq(cursor, bytes(s).length, "cursor");
        assertEq(inlineC, c, "inline coefficient");
        assertEq(inlineE, e, "inline exponent");
        Float float;
        (err, float) = this.parse(s);
        assertEq(err, ParseDecimalPrecisionLoss.selector, "error");
        assertEq(Float.unwrap(float), bytes32(0), "float");
    }

    function checkFail(string memory s, bytes4 selector, uint256 cursorAfter) internal view {
        (bytes4 err, uint256 cursor,,) = this.parseInline(s);
        assertEq(err, selector, "inline error");
        assertEq(cursor, cursorAfter, "cursor");
        Float float;
        (err, float) = this.parse(s);
        assertEq(err, selector, "error");
        assertEq(Float.unwrap(float), bytes32(0), "float");
    }

    /// Issue #341: 1e77 and 1e100 written out are Floats.
    function testParseIntegerPastInt256PowersOfTen() external view {
        checkExact(string.concat("1", zeros(77)), 1, 77, 1, 77);
        checkExact(string.concat("-1", zeros(77)), -1, 77, -1, 77);
        checkExact(string.concat("1", zeros(100)), 1, 100, 1, 100);
        checkExact(string.concat("-1", zeros(100)), -1, 100, -1, 100);
        checkExact(string.concat("000", "1", zeros(100)), 1, 100, 1, 100);
        checkExact(string.concat("-000", "3", zeros(100)), -3, 100, -3, 100);
        checkExact(string.concat("12345", zeros(200)), 12345, 200, 12345, 200);
    }

    /// The fallback starts exactly past int256: 5e76 fits it, 6e76 does not.
    function testParseIntegerPastInt256Boundary() external view {
        checkExact(string.concat("5", zeros(76)), 5e76, 0, 5e66, 10);
        checkExact(string.concat("6", zeros(76)), 6, 76, 6, 76);
        checkExact(string.concat("-6", zeros(76)), -6, 76, -6, 76);
        // int256.min fits int256, one past it does not.
        checkLoss(string.concat("-", INT256_MAX_PLUS_ONE), type(int256).min, 0);
        checkFail(string.concat("-", INT256_MAX_PLUS_TWO), ParseDecimalOverflow.selector, 78);
        checkLoss(INT256_MAX, type(int256).max, 0);
        checkFail(INT256_MAX_PLUS_ONE, ParseDecimalOverflow.selector, 77);
        // Trailing zeros do not help significant digits past int256.
        checkFail(string.concat(INT256_MAX_PLUS_ONE, "0"), ParseDecimalOverflow.selector, 78);
        // Significant digits within int256 but past int224 are no Float.
        checkLoss(string.concat(INT256_MAX, "0000"), type(int256).max, 4);
        checkLoss(string.concat("-", INT256_MAX_PLUS_ONE, "00"), type(int256).min, 2);
    }

    /// The int224 coefficient bounds followed by zeros are exact.
    function testParseIntegerPastInt256Int224Bounds() external view {
        int256 max = type(int224).max;
        int256 min = type(int224).min;
        checkExact(string.concat(Strings.toStringSigned(max), zeros(20)), max, 20, max, 20);
        checkExact(string.concat(Strings.toStringSigned(min), zeros(20)), min, 20, min, 20);
        checkExact(string.concat(Strings.toStringSigned(max), zeros(200)), max, 200, max, 200);
        // One past int224.max is no Float at any exponent.
        checkLoss(string.concat(Strings.toStringSigned(max + 1), zeros(20)), max + 1, 20);
    }

    /// The fraction after an integer part past int256.
    function testParseIntegerPastInt256Fraction() external view {
        string memory e77 = string.concat("1", zeros(77));
        checkExact(string.concat(e77, ".0"), 1, 77, 1, 77);
        checkExact(string.concat(e77, ".", zeros(100)), 1, 77, 1, 77);
        checkExact(string.concat(e77, ".000e-77"), 1, 0, 1, 0);
        checkFail(string.concat(e77, ".5"), ParseDecimalPrecisionLoss.selector, 80);
        checkFail(string.concat(e77, ".0001"), ParseDecimalPrecisionLoss.selector, 83);
        checkFail(string.concat(e77, ".1000"), ParseDecimalPrecisionLoss.selector, 83);
        checkFail(string.concat(e77, "."), MalformedDecimalPoint.selector, 79);
        checkFail(string.concat(e77, ".e1"), MalformedDecimalPoint.selector, 79);
        checkFail(string.concat(e77, ".-1"), MalformedDecimalPoint.selector, 79);
        // Significant digits past int256 report that before the fraction.
        checkFail(string.concat(INT256_MAX_PLUS_ONE, ".5"), ParseDecimalOverflow.selector, 77);
        // What follows is left to the caller.
        (bytes4 err, uint256 cursor, int256 c, int256 e) = this.parseInline(string.concat(e77, ".00x"));
        assertEq(err, bytes4(0));
        assertEq(cursor, 81);
        assertEq(c, 1);
        assertEq(e, 77);
        (err,) = this.parse(string.concat(e77, ".00x"));
        assertEq(err, ParseDecimalFloatExcessCharacters.selector);
    }

    /// The zeros moved into the exponent add to the written exponent.
    function testParseIntegerPastInt256Exponent() external view {
        string memory e80 = string.concat("1", zeros(80));
        checkExact(string.concat(e80, "e-80"), 1, 0, 1, 0);
        checkExact(string.concat(e80, "e2147483567"), 1, 2147483647, 1, type(int32).max);
        checkExact(string.concat(e80, "e-2147483728"), 1, -2147483648, 1, type(int32).min);
        checkExact(string.concat("-", e80, ".0E+3"), -1, 83, -1, 83);
        checkLoss(string.concat(e80, "e-2147483729"), 1, -2147483649);
    }

    /// Issue #341: zero takes an exponent of any size.
    function testParseZeroHugeExponent() external view {
        string[6] memory literals = [
            string.concat("0e", INT256_MAX_PLUS_ONE),
            string.concat("0e-", INT256_MAX_PLUS_TWO),
            string.concat("-0.000E+", INT256_MAX_PLUS_ONE, "000"),
            string.concat("000e", INT256_MAX_PLUS_ONE),
            string.concat("0.0e-", "9", zeros(200)),
            string.concat("0e", INT256_MAX)
        ];
        for (uint256 i = 0; i < literals.length; i++) {
            checkExact(literals[i], 0, 0, 0, 0);
        }
    }

    /// A nonzero coefficient with an exponent past int256 is no Float.
    function testParseNonZeroHugeExponent() external view {
        string memory s = string.concat("1e", INT256_MAX_PLUS_ONE);
        checkFail(s, ParseDecimalOverflow.selector, bytes(s).length);
        s = string.concat("-0.1e-", INT256_MAX_PLUS_TWO);
        checkFail(s, ParseDecimalOverflow.selector, bytes(s).length);
        s = string.concat("1", zeros(80), "e", INT256_MAX_PLUS_ONE);
        checkFail(s, ParseDecimalOverflow.selector, bytes(s).length);
    }

    /// Any int224 followed by any number of zeros parses to exactly its value.
    function testParseIntegerTrailingZerosFuzz(int224 c, uint8 z) external view {
        string memory s = string.concat(Strings.toStringSigned(c), zeros(z));
        (bytes4 err, Float float) = this.parse(s);
        assertEq(err, bytes4(0), "error");
        if (c == 0) {
            assertEq(Float.unwrap(float), bytes32(0), "zero");
        } else {
            assertTrue(float.eq(LibDecimalFloat.packLossless(c, int256(uint256(z)))), "value");
        }
    }
}
