// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 thedavidmeister
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {Float, LibDecimalFloat} from "src/lib/LibDecimalFloat.sol";
import {LibFormatDecimalFloat} from "src/lib/format/LibFormatDecimalFloat.sol";
import {LibParseDecimalFloat} from "src/lib/parse/LibParseDecimalFloat.sol";

/// @title LibFormatDecimalFloatToDecimalStringTest
/// @notice Test contract for verifying the functionality of LibFormatDecimalFloat
/// @dev Tests both the stack and memory versions of formatting functions and round-trip conversions
contract LibFormatDecimalFloatToDecimalStringTest is Test {
    using LibDecimalFloat for Float;
    using LibFormatDecimalFloat for Float;

    function checkFormat(int256 signedCoefficient, int256 exponent, string memory expected) internal pure {
        string memory actual =
            LibFormatDecimalFloat.toDecimalString(LibDecimalFloat.packLossless(signedCoefficient, exponent));
        assertEq(actual, expected, "Formatted value mismatch");
    }

    function toString(Float float) external pure returns (string memory) {
        return LibFormatDecimalFloat.toDecimalString(float);
    }

    /// Test round tripping a value through parse and format.
    function testFormatDecimalRoundTripNonNegative(uint256 value) external pure {
        value = bound(value, 0, uint256(int256(type(int224).max)));
        Float float = LibDecimalFloat.fromFixedDecimalLosslessPacked(value, 18);
        string memory formatted = LibFormatDecimalFloat.toDecimalString(float);
        (bytes4 errorCode, Float parsed) = LibParseDecimalFloat.parseDecimalFloat(formatted);
        assertEq(errorCode, 0, "Parse error");
        assertTrue(float.eq(parsed), "Round trip failed");
        // Canonicalization: format(parse(format(x))) == format(x)
        string memory reFormatted = LibFormatDecimalFloat.toDecimalString(parsed);
        assertEq(formatted, reFormatted, "Formatting not canonical");
    }

    /// Negative matches positive.
    function testFormatDecimalRoundTripNegative(int256 value) external pure {
        value = bound(value, 1, int256(type(int128).max));
        Float float = LibDecimalFloat.packLossless(value, 18);
        string memory formatted = float.toDecimalString();
        float = float.minus();
        string memory formattedNeg = float.toDecimalString();

        assertEq(string.concat("-", formatted), formattedNeg, "Negative format mismatch");
    }

    /// Test some specific examples.
    function testFormatDecimalExamples() external pure {
        // pos decs
        checkFormat(123456789012345678901234567890, 0, "1.2345678901234567890123456789e29");
        checkFormat(123456789012345678901234567890, -1, "1.2345678901234567890123456789e28");
        checkFormat(123456789012345678901234567890, -2, "1.2345678901234567890123456789e27");
        checkFormat(123456789012345678901234567890, -3, "1.2345678901234567890123456789e26");
        checkFormat(123456789012345678901234567890, -4, "1.2345678901234567890123456789e25");
        checkFormat(123456789012345678901234567890, -5, "1.2345678901234567890123456789e24");
        checkFormat(123456789012345678901234567890, -6, "1.2345678901234567890123456789e23");

        // zeros
        checkFormat(0, 0, "0");
        checkFormat(0, -1, "0");
        checkFormat(0, -2, "0");
        checkFormat(0, -3, "0");
        checkFormat(0, 1, "0");
        checkFormat(0, 2, "0");
        checkFormat(0, 3, "0");

        // neg decs
        checkFormat(-123456789012345678901234567890, 0, "-1.2345678901234567890123456789e29");
        checkFormat(-123456789012345678901234567890, -1, "-1.2345678901234567890123456789e28");
        checkFormat(-123456789012345678901234567890, -2, "-1.2345678901234567890123456789e27");
        checkFormat(-123456789012345678901234567890, -3, "-1.2345678901234567890123456789e26");
        checkFormat(-123456789012345678901234567890, -4, "-1.2345678901234567890123456789e25");
        checkFormat(-123456789012345678901234567890, -5, "-1.2345678901234567890123456789e24");
        checkFormat(-123456789012345678901234567890, -6, "-1.2345678901234567890123456789e23");

        // one
        checkFormat(1, 0, "1");

        // 100
        checkFormat(100, 0, "100");
        checkFormat(10, 1, "100");
        checkFormat(1, 2, "100");
        checkFormat(1000, -1, "100");

        // -100
        checkFormat(-100, 0, "-100");
        checkFormat(-10, 1, "-100");
        checkFormat(-1, 2, "-100");
        checkFormat(-1000, -1, "-100");

        // 0.1
        checkFormat(1, -1, "0.1");
        checkFormat(10, -2, "0.1");
        checkFormat(100, -3, "0.1");
        checkFormat(1000, -4, "0.1");

        // -0.1
        checkFormat(-1, -1, "-0.1");
        checkFormat(-10, -2, "-0.1");
        checkFormat(-100, -3, "-0.1");
        checkFormat(-1000, -4, "-0.1");

        // 0.101
        checkFormat(101, -3, "0.101");
        checkFormat(1010, -4, "0.101");
        checkFormat(10100, -5, "0.101");
        checkFormat(101000, -6, "0.101");

        // -0.101
        checkFormat(-101, -3, "-0.101");
        checkFormat(-1010, -4, "-0.101");
        checkFormat(-10100, -5, "-0.101");
        checkFormat(-101000, -6, "-0.101");

        // 1.1
        checkFormat(11, -1, "1.1");
        checkFormat(110, -2, "1.1");
        checkFormat(1100, -3, "1.1");
        checkFormat(11000, -4, "1.1");

        // -1.1
        checkFormat(-11, -1, "-1.1");
        checkFormat(-110, -2, "-1.1");
        checkFormat(-1100, -3, "-1.1");
        checkFormat(-11000, -4, "-1.1");

        // 9 sig figs
        checkFormat(123456789, 0, "123456789");
        checkFormat(-123456789, 0, "-123456789");
        checkFormat(123456789, -1, "12345678.9");
        checkFormat(-123456789, -1, "-12345678.9");
        checkFormat(12345678, 1, "123456780");
        checkFormat(-12345678, 1, "-123456780");

        // 10 sig figs
        checkFormat(1234567890, 0, "1.23456789e9");
        checkFormat(-1234567890, 0, "-1.23456789e9");
        checkFormat(123456789, 1, "1.23456789e9");
        checkFormat(-123456789, 1, "-1.23456789e9");
        checkFormat(1, -10, "1e-10");

        // examples from fuzz
        checkFormat(1019001501928, -18, "1.019001501928e-6");
        checkFormat(-1019001501928, -18, "-1.019001501928e-6");

        // pure powers of 10 at the cutoff
        checkFormat(1000000000, 0, "1e9");
        checkFormat(-1000000000, 0, "-1e9");
        // extreme small/large magnitudes still choose scientific
        checkFormat(1, -76, "1e-76");
        checkFormat(-1, -76, "-1e-76");
        checkFormat(1, 76, "1e76");
        checkFormat(-1, 76, "-1e76");
    }
}
