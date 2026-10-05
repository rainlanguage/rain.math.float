// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {LibParseDecimalFloat} from "src/lib/parse/LibParseDecimalFloat.sol";
import {LibBytes, Pointer} from "rain-solmem-0.1.28/src/lib/LibBytes.sol";
import {Strings} from "@openzeppelin-contracts-5.7.0/utils/Strings.sol";
import {ParseEmptyDecimalString, ParseDecimalOverflow} from "rain-string-0.3.9/src/error/ErrParse.sol";
import {ParseDecimalFloatExcessCharacters} from "src/error/ErrParse.sol";
import {Float, LibDecimalFloat} from "src/lib/LibDecimalFloat.sol";

contract LibParseDecimalFloatCommasTest is Test {
    using LibBytes for bytes;
    using Strings for uint256;
    using LibDecimalFloat for Float;

    function parseInline(string memory data, bool commas)
        internal
        pure
        returns (bytes4 errorSelector, uint256 cursorMove, int256 signedCoefficient, int256 exponent)
    {
        uint256 start = Pointer.unwrap(bytes(data).dataPointer());
        uint256 cursor;
        (errorSelector, cursor, signedCoefficient, exponent) =
            LibParseDecimalFloat.parseDecimalFloatInline(start, Pointer.unwrap(bytes(data).endDataPointer()), commas);
        cursorMove = cursor - start;
    }

    function checkCommas(string memory data, int256 expectedCoefficient, int256 expectedExponent, uint256 expectedMove)
        internal
        pure
    {
        (bytes4 errorSelector, uint256 cursorMove, int256 signedCoefficient, int256 exponent) = parseInline(data, true);
        assertEq(errorSelector, bytes4(0), "selector");
        assertEq(signedCoefficient, expectedCoefficient, "coefficient");
        assertEq(exponent, expectedExponent, "exponent");
        assertEq(cursorMove, expectedMove, "cursor");
    }

    function checkCommasFail(string memory data, bytes4 expectedSelector, uint256 expectedMove) internal pure {
        (bytes4 errorSelector, uint256 cursorMove,,) = parseInline(data, true);
        assertEq(errorSelector, expectedSelector, "selector");
        assertEq(cursorMove, expectedMove, "cursor");
    }

    /// Independent reference grouping: recursive on the thousands quotient.
    function grouped(uint256 value) internal pure returns (string memory) {
        if (value < 1000) {
            return value.toString();
        }
        uint256 group = value % 1000;
        string memory pad = group < 10 ? "00" : group < 100 ? "0" : "";
        return string.concat(grouped(value / 1000), ",", pad, group.toString());
    }

    function testParseCommasExamples() external pure {
        checkCommas("1,000", 1000, 0, 5);
        checkCommas("-1,000", -1000, 0, 6);
        checkCommas("12,345", 12345, 0, 6);
        checkCommas("123,456", 123456, 0, 7);
        checkCommas("1,234,567", 1234567, 0, 9);
        checkCommas("-1,234,567.89", -123456789, -2, 13);
        checkCommas("1,000.5", 10005, -1, 7);
        checkCommas("1,000e3", 1000, 3, 7);
        checkCommas("1,000.25e-2", 100025, -4, 11);
        checkCommas("999,999,999", 999999999, 0, 11);
        checkCommas("0,001", 1, 0, 5);
        checkCommas("-0,001", -1, 0, 6);
        checkCommas("000,000", 0, 0, 7);
        checkCommas("1,000,000,000,000,000,000", 1e18, 0, 25);
    }

    /// A comma outside the grouping ends the literal before that comma.
    function testParseCommasStopBeforeUngroupedComma() external pure {
        checkCommas("1,2", 1, 0, 1);
        checkCommas("1,00", 1, 0, 1);
        checkCommas("1,0000", 1, 0, 1);
        checkCommas("1000,000", 1000, 0, 4);
        checkCommas("1,000,0", 1000, 0, 5);
        checkCommas("1,000,", 1000, 0, 5);
        checkCommas("1,", 1, 0, 1);
        checkCommas("1,,000", 1, 0, 1);
        checkCommas("1,a00", 1, 0, 1);
        checkCommas("1.000,000", 1, 0, 5);
        checkCommas("1e1,000", 1, 1, 3);
        checkCommas("1,000 ,000", 1000, 0, 5);
        checkCommasFail(",000", ParseEmptyDecimalString.selector, 0);
        checkCommasFail("-,000", ParseEmptyDecimalString.selector, 1);
    }

    /// Without the flag no comma is ever consumed.
    function testParseNoCommasStopsAtComma() external pure {
        (bytes4 errorSelector, uint256 cursorMove, int256 signedCoefficient,) = parseInline("1,000", false);
        assertEq(errorSelector, bytes4(0));
        assertEq(cursorMove, 1);
        assertEq(signedCoefficient, 1);

        (bytes4 wrapped, Float float) = LibParseDecimalFloat.parseDecimalFloat("1,000");
        assertEq(wrapped, ParseDecimalFloatExcessCharacters.selector);
        assertEq(Float.unwrap(float), 0);

        (wrapped, float) = LibParseDecimalFloat.parseDecimalFloat("1,000", false);
        assertEq(wrapped, ParseDecimalFloatExcessCharacters.selector);
        assertEq(Float.unwrap(float), 0);
    }

    function testParseCommasPacked() external pure {
        (bytes4 errorSelector, Float float) = LibParseDecimalFloat.parseDecimalFloat("-1,234,567.89", true);
        assertEq(errorSelector, bytes4(0));
        assertTrue(float.eq(LibDecimalFloat.packLossless(-123456789, -2)));

        (errorSelector, float) = LibParseDecimalFloat.parseDecimalFloat("1,0000", true);
        assertEq(errorSelector, ParseDecimalFloatExcessCharacters.selector);
        assertEq(Float.unwrap(float), 0);
    }

    /// Grouping overflows exactly where the same digits ungrouped overflow.
    function testParseCommasOverflowBoundary() external pure {
        uint256 max = uint256(type(int256).max);
        checkCommas(grouped(max), type(int256).max, 0, bytes(grouped(max)).length);
        checkCommasFail(grouped(max + 1), ParseDecimalOverflow.selector, bytes(grouped(max + 1)).length);
        string memory minString = string.concat("-", grouped(max + 1));
        checkCommas(minString, type(int256).min, 0, bytes(minString).length);
        string memory belowMin = string.concat("-", grouped(max + 2));
        checkCommasFail(belowMin, ParseDecimalOverflow.selector, bytes(belowMin).length);
        checkCommasFail(
            grouped(type(uint256).max), ParseDecimalOverflow.selector, bytes(grouped(type(uint256).max)).length
        );
    }

    /// A grouped literal parses to exactly what its ungrouped digits parse to,
    /// overflow included, consuming the whole grouped string on success.
    function testParseCommasMatchUngrouped(uint256 value, bool isNeg, uint8 suffixChoice) external pure {
        string[4] memory suffixes = ["", ".5", "e-3", ".0250e2"];
        string memory suffix = suffixes[suffixChoice % 4];
        string memory sign = isNeg ? "-" : "";
        string memory groupedInput = string.concat(sign, grouped(value), suffix);
        string memory plainInput = string.concat(sign, value.toString(), suffix);

        (bytes4 groupedSelector, uint256 groupedMove, int256 groupedCoefficient, int256 groupedExponent) =
            parseInline(groupedInput, true);
        (bytes4 plainSelector, uint256 plainMove, int256 plainCoefficient, int256 plainExponent) =
            parseInline(plainInput, false);

        assertEq(groupedSelector, plainSelector, "selector");
        assertEq(groupedCoefficient, plainCoefficient, "coefficient");
        assertEq(groupedExponent, plainExponent, "exponent");
        if (plainSelector == bytes4(0)) {
            assertEq(plainMove, bytes(plainInput).length);
            assertEq(groupedMove, bytes(groupedInput).length);
        }
    }

    /// Any input without a comma parses identically with and without the flag.
    function testParseCommasFlagIrrelevantWithoutComma(bytes memory data) external pure {
        for (uint256 i = 0; i < data.length; i++) {
            if (data[i] == ",") {
                data[i] = "0";
            }
        }
        (bytes4 aSelector, uint256 aMove, int256 aCoefficient, int256 aExponent) = parseInline(string(data), true);
        (bytes4 bSelector, uint256 bMove, int256 bCoefficient, int256 bExponent) = parseInline(string(data), false);
        assertEq(aSelector, bSelector);
        assertEq(aMove, bMove);
        assertEq(aCoefficient, bCoefficient);
        assertEq(aExponent, bExponent);
    }
}
