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

    function checkFormat(int256 signedCoefficient, int256 exponent, uint256 sigFigsLimit, string memory expected)
        internal
        pure
    {
        string memory actual = LibFormatDecimalFloat.toDecimalString(
            LibDecimalFloat.packLossless(signedCoefficient, exponent), sigFigsLimit
        );
        assertEq(actual, expected, "Formatted value mismatch");
    }

    /// Test round tripping a value through parse and format.
    function testFormatDecimalRoundTripNonNegative(uint256 value, uint256 sigFigsLimit) external pure {
        value = bound(value, 0, uint256(int256(type(int224).max)));
        Float float = LibDecimalFloat.fromFixedDecimalLosslessPacked(value, 18);
        string memory formatted = LibFormatDecimalFloat.toDecimalString(float, sigFigsLimit);
        (bytes4 errorCode, Float parsed) = LibParseDecimalFloat.parseDecimalFloat(formatted);
        assertEq(errorCode, 0, "Parse error");
        assertTrue(float.eq(parsed), "Round trip failed");
        // Canonicalization: format(parse(format(x))) == format(x)
        string memory reFormatted = LibFormatDecimalFloat.toDecimalString(parsed, sigFigsLimit);
        assertEq(formatted, reFormatted, "Formatting not canonical");
    }

    /// Negative matches positive.
    function testFormatDecimalRoundTripNegative(int256 value, uint256 sigFigsLimit) external pure {
        value = bound(value, 1, int256(type(int128).max));
        Float float = LibDecimalFloat.fromFixedDecimalLosslessPacked(uint256(value), 18);
        string memory formatted = float.toDecimalString(sigFigsLimit);
        float = float.minus();
        string memory formattedNeg = float.toDecimalString(sigFigsLimit);

        assertEq(string.concat("-", formatted), formattedNeg, "Negative format mismatch");
        // Parse/eq for negative path as well
        (bytes4 err, Float parsedNeg) = LibParseDecimalFloat.parseDecimalFloat(formattedNeg);
        assertEq(err, 0, "Parse error (neg)");
        assertTrue(float.eq(parsedNeg), "Round trip failed (neg)");
    }

    /// Test some specific examples.
    function testFormatDecimalExamples() external pure {
        // pos decs
        checkFormat(123456789012345678901234567890, 0, 9, "1.2345678901234567890123456789e29");
        checkFormat(123456789012345678901234567890, -1, 9, "1.2345678901234567890123456789e28");
        checkFormat(123456789012345678901234567890, -2, 9, "1.2345678901234567890123456789e27");
        checkFormat(123456789012345678901234567890, -3, 9, "1.2345678901234567890123456789e26");
        checkFormat(123456789012345678901234567890, -4, 9, "1.2345678901234567890123456789e25");
        checkFormat(123456789012345678901234567890, -5, 9, "1.2345678901234567890123456789e24");
        checkFormat(123456789012345678901234567890, -6, 9, "1.2345678901234567890123456789e23");

        // zeros
        checkFormat(0, 0, 9, "0");
        checkFormat(0, -1, 9, "0");
        checkFormat(0, -2, 9, "0");
        checkFormat(0, -3, 9, "0");
        checkFormat(0, 1, 9, "0");
        checkFormat(0, 2, 9, "0");
        checkFormat(0, 3, 9, "0");

        // neg decs
        checkFormat(-123456789012345678901234567890, 0, 9, "-1.2345678901234567890123456789e29");
        checkFormat(-123456789012345678901234567890, -1, 9, "-1.2345678901234567890123456789e28");
        checkFormat(-123456789012345678901234567890, -2, 9, "-1.2345678901234567890123456789e27");
        checkFormat(-123456789012345678901234567890, -3, 9, "-1.2345678901234567890123456789e26");
        checkFormat(-123456789012345678901234567890, -4, 9, "-1.2345678901234567890123456789e25");
        checkFormat(-123456789012345678901234567890, -5, 9, "-1.2345678901234567890123456789e24");
        checkFormat(-123456789012345678901234567890, -6, 9, "-1.2345678901234567890123456789e23");

        // one
        checkFormat(1, 0, 9, "1");

        // 100
        checkFormat(100, 0, 9, "100");
        checkFormat(10, 1, 9, "100");
        checkFormat(1, 2, 9, "100");
        checkFormat(1000, -1, 9, "100");

        // -100
        checkFormat(-100, 0, 9, "-100");
        checkFormat(-10, 1, 9, "-100");
        checkFormat(-1, 2, 9, "-100");
        checkFormat(-1000, -1, 9, "-100");

        // 0.1
        checkFormat(1, -1, 9, "0.1");
        checkFormat(10, -2, 9, "0.1");
        checkFormat(100, -3, 9, "0.1");
        checkFormat(1000, -4, 9, "0.1");

        // -0.1
        checkFormat(-1, -1, 9, "-0.1");
        checkFormat(-10, -2, 9, "-0.1");
        checkFormat(-100, -3, 9, "-0.1");
        checkFormat(-1000, -4, 9, "-0.1");

        // 0.101
        checkFormat(101, -3, 9, "0.101");
        checkFormat(1010, -4, 9, "0.101");
        checkFormat(10100, -5, 9, "0.101");
        checkFormat(101000, -6, 9, "0.101");

        // -0.101
        checkFormat(-101, -3, 9, "-0.101");
        checkFormat(-1010, -4, 9, "-0.101");
        checkFormat(-10100, -5, 9, "-0.101");
        checkFormat(-101000, -6, 9, "-0.101");

        // 1.1
        checkFormat(11, -1, 9, "1.1");
        checkFormat(110, -2, 9, "1.1");
        checkFormat(1100, -3, 9, "1.1");
        checkFormat(11000, -4, 9, "1.1");

        // -1.1
        checkFormat(-11, -1, 9, "-1.1");
        checkFormat(-110, -2, 9, "-1.1");
        checkFormat(-1100, -3, 9, "-1.1");
        checkFormat(-11000, -4, 9, "-1.1");

        // 9 sig figs
        checkFormat(123456789, 0, 9, "123456789");
        checkFormat(-123456789, 0, 9, "-123456789");
        checkFormat(123456789, -1, 9, "12345678.9");
        checkFormat(-123456789, -1, 9, "-12345678.9");
        checkFormat(12345678, 1, 9, "123456780");
        checkFormat(-12345678, 1, 9, "-123456780");

        // 10 sig figs
        checkFormat(1234567890, 0, 9, "1.23456789e9");
        checkFormat(-1234567890, 0, 9, "-1.23456789e9");
        checkFormat(123456789, 1, 9, "1.23456789e9");
        checkFormat(-123456789, 1, 9, "-1.23456789e9");
        checkFormat(1, -10, 9, "1e-10");

        // examples from fuzz
        checkFormat(1019001501928, -18, 9, "1.019001501928e-6");
        checkFormat(-1019001501928, -18, 9, "-1.019001501928e-6");

        // pure powers of 10 at the cutoff
        checkFormat(1000000000, 0, 9, "1e9");
        checkFormat(-1000000000, 0, 9, "-1e9");
        // extreme small/large magnitudes still choose scientific
        checkFormat(1, -76, 9, "1e-76");
        checkFormat(-1, -76, 9, "-1e-76");
        checkFormat(1, 76, 9, "1e76");
        checkFormat(-1, 76, 9, "-1e76");

        // impossible sig figs.
        checkFormat(1, 200, 1, "1e200");
        // we can't actually fit 200 zeros into the binary representation so
        // even though the threshold is 200 we still use scientific notation.
        checkFormat(1, 200, 200, "1e200");
    }

    function testFormatDecimalCustomSigFigs() external pure {
        // Force rounding under a tighter sig-figs limit.
        Float f = LibDecimalFloat.packLossless(12345678, 0);
        string memory s = LibFormatDecimalFloat.toDecimalString(f, 5);
        // Verify the explicit limit path (adjust expected if rounding policy differs).
        assertEq(s, "1.2345678e7", "Custom sig-figs not applied");
    }
}
