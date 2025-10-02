// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
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

    function checkFormat(int256 signedCoefficient, int256 exponent, bool scientific, string memory expected)
        internal
        pure
    {
        string memory actual =
            LibFormatDecimalFloat.toDecimalString(LibDecimalFloat.packLossless(signedCoefficient, exponent), scientific);
        assertEq(actual, expected, "Formatted value mismatch");
    }

    function checkRoundFromString(string memory s, Float expected, bool scientific) internal pure {
        (bytes4 err, Float parsed) = LibParseDecimalFloat.parseDecimalFloat(s);
        assertEq(err, 0, "Parse error");
        assertTrue(expected.eq(parsed), "Round trip failed");
        // Canonicalization: format(parse(s)) == s
        string memory reFormatted = LibFormatDecimalFloat.toDecimalString(parsed, scientific);
        assertEq(s, reFormatted, "Formatting not canonical");
    }

    /// Test round tripping examples.
    function testFormatDecimalRoundTripExamples() external pure {
        checkRoundFromString(
            "1.2345678901234567890123456789e29", LibDecimalFloat.packLossless(123456789012345678901234567890, 0), true
        );
        checkRoundFromString("0", LibDecimalFloat.packLossless(0, 0), true);
        checkRoundFromString("0", LibDecimalFloat.packLossless(0, 0), false);
        checkRoundFromString(
            "-1.2345678901234567890123456789e29", LibDecimalFloat.packLossless(-123456789012345678901234567890, 0), true
        );
        checkRoundFromString("1", LibDecimalFloat.packLossless(1, 0), false);
        checkRoundFromString("1", LibDecimalFloat.packLossless(1, 0), true);
        checkRoundFromString("-1", LibDecimalFloat.packLossless(-1, 0), false);
        checkRoundFromString("-1", LibDecimalFloat.packLossless(-1, 0), true);
        checkRoundFromString("100", LibDecimalFloat.packLossless(100, 0), false);
        checkRoundFromString("1e2", LibDecimalFloat.packLossless(100, 0), true);
        checkRoundFromString("-100", LibDecimalFloat.packLossless(-100, 0), false);
        checkRoundFromString("-1e2", LibDecimalFloat.packLossless(-100, 0), true);
        checkRoundFromString("0.01", LibDecimalFloat.packLossless(1, -2), false);
        checkRoundFromString("1e-2", LibDecimalFloat.packLossless(1, -2), true);
        checkRoundFromString("-0.01", LibDecimalFloat.packLossless(-1, -2), false);
        checkRoundFromString("-1e-2", LibDecimalFloat.packLossless(-1, -2), true);
        checkRoundFromString("0.1", LibDecimalFloat.packLossless(1, -1), false);
        checkRoundFromString("1e-1", LibDecimalFloat.packLossless(1, -1), true);
        checkRoundFromString("-1e-1", LibDecimalFloat.packLossless(-1, -1), true);
        checkRoundFromString("-0.1", LibDecimalFloat.packLossless(-1, -1), false);
        checkRoundFromString("0.101", LibDecimalFloat.packLossless(101, -3), false);
        checkRoundFromString("1.01e-1", LibDecimalFloat.packLossless(101, -3), true);
        checkRoundFromString("-0.101", LibDecimalFloat.packLossless(-101, -3), false);
        checkRoundFromString("-1.01e-1", LibDecimalFloat.packLossless(-101, -3), true);
        checkRoundFromString("1.1", LibDecimalFloat.packLossless(11, -1), false);
        checkRoundFromString("1.1", LibDecimalFloat.packLossless(11, -1), true);
        checkRoundFromString("-1.1", LibDecimalFloat.packLossless(-11, -1), false);
        checkRoundFromString("-1.1", LibDecimalFloat.packLossless(-11, -1), true);
        checkRoundFromString("123456789", LibDecimalFloat.packLossless(123456789, 0), false);
        checkRoundFromString("1.23456789e8", LibDecimalFloat.packLossless(123456789, 0), true);
        checkRoundFromString("-123456789", LibDecimalFloat.packLossless(-123456789, 0), false);
        checkRoundFromString("-1.23456789e8", LibDecimalFloat.packLossless(-123456789, 0), true);
        checkRoundFromString("1.23456789e9", LibDecimalFloat.packLossless(1234567890, 0), true);
        checkRoundFromString("123456789", LibDecimalFloat.packLossless(123456789, 0), false);
        checkRoundFromString("-1.23456789e9", LibDecimalFloat.packLossless(-1234567890, 0), true);
        checkRoundFromString("-123456789", LibDecimalFloat.packLossless(-123456789, 0), false);
        checkRoundFromString("1.019001501928e-6", LibDecimalFloat.packLossless(1019001501928, -18), true);
        checkRoundFromString("0.000001019001501928", LibDecimalFloat.packLossless(1019001501928, -18), false);
        checkRoundFromString("-1.019001501928e-6", LibDecimalFloat.packLossless(-1019001501928, -18), true);
        checkRoundFromString("-0.000001019001501928", LibDecimalFloat.packLossless(-1019001501928, -18), false);
        checkRoundFromString("1e9", LibDecimalFloat.packLossless(1000000000, 0), true);
        checkRoundFromString("1000000000", LibDecimalFloat.packLossless(1000000000, 0), false);
        checkRoundFromString("-1e9", LibDecimalFloat.packLossless(-1000000000, 0), true);
        checkRoundFromString("-1000000000", LibDecimalFloat.packLossless(-1000000000, 0), false);
        checkRoundFromString("1e-76", LibDecimalFloat.packLossless(1, -76), true);
        checkRoundFromString("-1e-76", LibDecimalFloat.packLossless(-1, -76), true);
        checkRoundFromString("1e76", LibDecimalFloat.packLossless(1, 76), true);
        checkRoundFromString("-1e76", LibDecimalFloat.packLossless(-1, 76), true);
        checkRoundFromString("1e200", LibDecimalFloat.packLossless(1, 200), true);
        checkRoundFromString("-1e200", LibDecimalFloat.packLossless(-1, 200), true);
    }

    /// Test round tripping a value through parse and format.
    function testFormatDecimalRoundTripNonNegative(uint256 value, bool scientific) external pure {
        value = bound(value, 0, uint256(int256(type(int224).max)));
        Float float = LibDecimalFloat.fromFixedDecimalLosslessPacked(value, 18);
        string memory formatted = LibFormatDecimalFloat.toDecimalString(float, scientific);
        (bytes4 errorCode, Float parsed) = LibParseDecimalFloat.parseDecimalFloat(formatted);
        assertEq(errorCode, 0, "Parse error");
        assertTrue(float.eq(parsed), "Round trip failed");
        // Canonicalization: format(parse(format(x))) == format(x)
        string memory reFormatted = LibFormatDecimalFloat.toDecimalString(parsed, scientific);
        assertEq(formatted, reFormatted, "Formatting not canonical");
    }

    /// Negative matches positive.
    function testFormatDecimalRoundTripNegative(int256 value, bool scientific) external pure {
        value = bound(value, 1, int256(type(int128).max));
        // value [1, int256(type(int128).max)]
        // forge-lint: disable-next-line(unsafe-typecast)
        Float float = LibDecimalFloat.fromFixedDecimalLosslessPacked(uint256(value), 18);
        string memory formatted = float.toDecimalString(scientific);
        float = float.minus();
        string memory formattedNeg = float.toDecimalString(scientific);

        assertEq(string.concat("-", formatted), formattedNeg, "Negative format mismatch");
        // Parse/eq for negative path as well
        (bytes4 err, Float parsedNeg) = LibParseDecimalFloat.parseDecimalFloat(formattedNeg);
        assertEq(err, 0, "Parse error (neg)");
        assertTrue(float.eq(parsedNeg), "Round trip failed (neg)");
        // Canonicalization for negative: format(parse(s)) == s
        string memory reFormattedNeg = LibFormatDecimalFloat.toDecimalString(parsedNeg, scientific);
        assertEq(formattedNeg, reFormattedNeg, "Formatting not canonical (neg)");
    }

    /// Test some specific examples.
    function testFormatDecimalExamples() external pure {
        // pos decs
        checkFormat(123456789012345678901234567890, 0, true, "1.2345678901234567890123456789e29");
        checkFormat(123456789012345678901234567890, -1, true, "1.2345678901234567890123456789e28");
        checkFormat(123456789012345678901234567890, -2, true, "1.2345678901234567890123456789e27");
        checkFormat(123456789012345678901234567890, -3, true, "1.2345678901234567890123456789e26");
        checkFormat(123456789012345678901234567890, -4, true, "1.2345678901234567890123456789e25");
        checkFormat(123456789012345678901234567890, -5, true, "1.2345678901234567890123456789e24");
        checkFormat(123456789012345678901234567890, -6, true, "1.2345678901234567890123456789e23");

        // zeros
        checkFormat(0, 0, true, "0");
        checkFormat(0, -1, true, "0");
        checkFormat(0, -2, true, "0");
        checkFormat(0, -3, true, "0");
        checkFormat(0, 1, true, "0");
        checkFormat(0, 2, true, "0");
        checkFormat(0, 3, true, "0");

        // neg decs
        checkFormat(-123456789012345678901234567890, 0, true, "-1.2345678901234567890123456789e29");
        checkFormat(-123456789012345678901234567890, -1, true, "-1.2345678901234567890123456789e28");
        checkFormat(-123456789012345678901234567890, -2, true, "-1.2345678901234567890123456789e27");
        checkFormat(-123456789012345678901234567890, -3, true, "-1.2345678901234567890123456789e26");
        checkFormat(-123456789012345678901234567890, -4, true, "-1.2345678901234567890123456789e25");
        checkFormat(-123456789012345678901234567890, -5, true, "-1.2345678901234567890123456789e24");
        checkFormat(-123456789012345678901234567890, -6, true, "-1.2345678901234567890123456789e23");

        // one
        checkFormat(1, 0, true, "1");

        // 100
        checkFormat(100, 0, false, "100");
        checkFormat(10, 1, false, "100");
        checkFormat(1, 2, false, "100");
        checkFormat(1000, -1, false, "100");

        // -100
        checkFormat(-100, 0, false, "-100");
        checkFormat(-10, 1, false, "-100");
        checkFormat(-1, 2, false, "-100");
        checkFormat(-1000, -1, false, "-100");

        // 0.01
        checkFormat(1, -2, false, "0.01");
        checkFormat(10, -3, false, "0.01");
        checkFormat(100, -4, false, "0.01");
        checkFormat(1000, -5, false, "0.01");

        // -0.01
        checkFormat(-1, -2, false, "-0.01");
        checkFormat(-10, -3, false, "-0.01");
        checkFormat(-100, -4, false, "-0.01");
        checkFormat(-1000, -5, false, "-0.01");

        // 0.1
        checkFormat(1, -1, false, "0.1");
        checkFormat(10, -2, false, "0.1");
        checkFormat(100, -3, false, "0.1");
        checkFormat(1000, -4, false, "0.1");

        // -0.1
        checkFormat(-1, -1, false, "-0.1");
        checkFormat(-10, -2, false, "-0.1");
        checkFormat(-100, -3, false, "-0.1");
        checkFormat(-1000, -4, false, "-0.1");

        // 0.101
        checkFormat(101, -3, false, "0.101");
        checkFormat(1010, -4, false, "0.101");
        checkFormat(10100, -5, false, "0.101");
        checkFormat(101000, -6, false, "0.101");

        // -0.101
        checkFormat(-101, -3, false, "-0.101");
        checkFormat(-1010, -4, false, "-0.101");
        checkFormat(-10100, -5, false, "-0.101");
        checkFormat(-101000, -6, false, "-0.101");

        // 1.1
        checkFormat(11, -1, false, "1.1");
        checkFormat(110, -2, false, "1.1");
        checkFormat(1100, -3, false, "1.1");
        checkFormat(11000, -4, false, "1.1");

        // -1.1
        checkFormat(-11, -1, false, "-1.1");
        checkFormat(-110, -2, false, "-1.1");
        checkFormat(-1100, -3, false, "-1.1");
        checkFormat(-11000, -4, false, "-1.1");

        // 9 sig figs
        checkFormat(123456789, 0, false, "123456789");
        checkFormat(-123456789, 0, false, "-123456789");
        checkFormat(123456789, -1, false, "12345678.9");
        checkFormat(-123456789, -1, false, "-12345678.9");
        checkFormat(12345678, 1, false, "123456780");
        checkFormat(-12345678, 1, false, "-123456780");

        // 10 sig figs
        checkFormat(1234567890, 0, true, "1.23456789e9");
        checkFormat(-1234567890, 0, true, "-1.23456789e9");
        checkFormat(123456789, 1, true, "1.23456789e9");
        checkFormat(-123456789, 1, true, "-1.23456789e9");
        checkFormat(1, -10, true, "1e-10");

        // examples from fuzz
        checkFormat(1019001501928, -18, true, "1.019001501928e-6");
        checkFormat(-1019001501928, -18, true, "-1.019001501928e-6");

        // pure powers of 10 at the cutoff
        checkFormat(1000000000, 0, true, "1e9");
        checkFormat(-1000000000, 0, true, "-1e9");
        // extreme small/large magnitudes still choose scientific
        checkFormat(1, -76, true, "1e-76");
        checkFormat(-1, -76, true, "-1e-76");
        checkFormat(1, 76, true, "1e76");
        checkFormat(-1, 76, true, "-1e76");

        // impossible sig figs.
        checkFormat(1, 200, true, "1e200");
        // we can't actually fit 200 zeros into the binary representation so
        // even though the threshold is 200 we still use scientific notation.
        checkFormat(1, 200, true, "1e200");
    }
}
