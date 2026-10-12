// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {Float, LibDecimalFloat} from "src/lib/LibDecimalFloat.sol";
import {LibFormatDecimalFloat} from "src/lib/format/LibFormatDecimalFloat.sol";
import {LibParseDecimalFloat} from "src/lib/parse/LibParseDecimalFloat.sol";
import {UnformatableExponent} from "src/error/ErrFormat.sol";
import {Strings} from "@openzeppelin-contracts-5.7.0/utils/Strings.sol";
import {LibExactFloat} from "test/lib/LibExactFloat.sol";

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
        string memory actual = LibFormatDecimalFloat.toDecimalString(
            LibDecimalFloat.packLossless(signedCoefficient, exponent), scientific
        );
        assertEq(actual, expected, "Formatted value mismatch");
    }

    /// Independent rendering of `signedCoefficient × 10^exponent`, built from
    /// the coefficient's decimal digits with no call into the formatter.
    /// Plain: the digits with the point placed `exponent` places from the
    /// right, trailing fractional zeros dropped. Scientific: the significant
    /// digits as `d.ddd` and `e` the exponent of the leading digit, omitted
    /// when zero.
    function expectedFormat(int256 signedCoefficient, int256 exponent, bool scientific)
        internal
        pure
        returns (string memory)
    {
        return
            expectedFormatMagnitude(signedCoefficient < 0, LibExactFloat.abs(signedCoefficient), exponent, scientific);
    }

    /// `expectedFormat` for `±absCoef × 10^exponent`, any uint256 magnitude.
    function expectedFormatMagnitude(bool negative, uint256 absCoef, int256 exponent, bool scientific)
        internal
        pure
        returns (string memory)
    {
        if (absCoef == 0) {
            return "0";
        }
        bytes memory raw = bytes(Strings.toString(absCoef));
        uint256 sigK = raw.length;
        while (raw[sigK - 1] == "0") {
            sigK--;
        }
        bytes memory sig = new bytes(sigK);
        for (uint256 i = 0; i < sigK; i++) {
            sig[i] = raw[i];
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 sigExponent = exponent + int256(raw.length - sigK);
        string memory body;
        if (scientific) {
            bytes memory fraction = new bytes(sigK - 1);
            for (uint256 i = 1; i < sigK; i++) {
                fraction[i - 1] = sig[i];
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 leadExponent = sigExponent + int256(sigK) - 1;
            body = string.concat(
                string(abi.encodePacked(sig[0])),
                sigK > 1 ? string.concat(".", string(fraction)) : "",
                leadExponent == 0 ? "" : string.concat("e", Strings.toStringSigned(leadExponent))
            );
        } else if (sigExponent >= 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            body = string.concat(string(sig), zeros(uint256(sigExponent)));
        } else {
            // forge-lint: disable-next-line(unsafe-typecast)
            body = placeDecimalPoint(string(sig), uint256(-sigExponent));
        }
        return string.concat(negative ? "-" : "", body);
    }

    function zeros(uint256 n) internal pure returns (string memory) {
        bytes memory z = new bytes(n);
        for (uint256 i = 0; i < n; i++) {
            z[i] = "0";
        }
        return string(z);
    }

    /// The oracle against hand-written renderings, so a defect in it cannot
    /// pass silently through every fuzz that uses it.
    function testExpectedFormatOracle() external pure {
        assertEq(expectedFormat(0, 5, true), "0");
        assertEq(expectedFormat(1, 0, true), "1");
        assertEq(expectedFormat(1, 0, false), "1");
        assertEq(expectedFormat(-1200, -5, true), "-1.2e-2");
        assertEq(expectedFormat(-1200, -5, false), "-0.012");
        assertEq(expectedFormat(1200, -2, true), "1.2e1");
        assertEq(expectedFormat(1200, -2, false), "12");
        assertEq(expectedFormat(105, -2, true), "1.05");
        assertEq(expectedFormat(105, -2, false), "1.05");
        assertEq(expectedFormat(105, 2, true), "1.05e4");
        assertEq(expectedFormat(105, 2, false), "10500");
        assertEq(expectedFormat(7, -4, false), "0.0007");
        assertEq(expectedFormat(7, -4, true), "7e-4");
        assertEq(expectedFormat(70, 3, true), "7e4");
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

    /// `value / 10^decimals` packed from fixed decimal, negated if `negative`,
    /// formats as the exact value when the pack is lossless and as the packed
    /// Float otherwise, which is the closest Float toward zero. The string
    /// parses back to the same value and re-formats to itself.
    function checkFixedDecimalRoundTrip(uint256 value, uint8 decimals, bool negative, bool scientific) internal pure {
        (Float float, bool lossless) = LibDecimalFloat.fromFixedDecimalLossyPacked(value, decimals);
        (int256 c, int256 e) = LibDecimalFloat.unpack(float);
        assertTrue(
            LibExactFloat.isNearestTowardZero(false, LibExactFloat.u512(value), -int256(uint256(decimals)), c, e),
            "nearest toward zero"
        );
        if (negative) {
            // The negative is the positive Float negated, which is exact.
            float = float.minus();
            (int256 nc, int256 ne) = LibDecimalFloat.unpack(float);
            assertTrue(LibExactFloat.eq(nc, ne, -c, e), "negated");
            (c, e) = (nc, ne);
        }
        string memory formatted = LibFormatDecimalFloat.toDecimalString(float, scientific);
        if (lossless) {
            assertEq(
                formatted,
                expectedFormatMagnitude(negative && value != 0, value, -int256(uint256(decimals)), scientific),
                "exact value format"
            );
        }
        assertEq(formatted, expectedFormat(c, e, scientific), "Formatted value mismatch");
        (bytes4 errorCode, Float parsed) = LibParseDecimalFloat.parseDecimalFloat(formatted);
        assertEq(errorCode, 0, "Parse error");
        (int256 pc, int256 pe) = LibDecimalFloat.unpack(parsed);
        assertTrue(LibExactFloat.eq(c, e, pc, pe), "Round trip failed");
        assertEq(LibFormatDecimalFloat.toDecimalString(parsed, scientific), formatted, "Formatting not canonical");
    }

    /// Test round tripping every fixed decimal value through format and parse.
    /// A uint8 `decimals` and a value below 1e78 keep the exponent inside the
    /// non-scientific cap, so both modes format.
    function testFormatDecimalRoundTripNonNegative(uint256 value, uint8 decimals, bool scientific) external pure {
        checkFixedDecimalRoundTrip(value, decimals, false, scientific);
    }

    /// Negative matches positive.
    function testFormatDecimalRoundTripNegative(uint256 value, uint8 decimals, bool scientific) external pure {
        checkFixedDecimalRoundTrip(value, decimals, true, scientific);
    }

    /// Values either side of the int224 bound, where the positive pack sheds
    /// to int224.max and its negation is not the closest negative Float.
    function testFormatDecimalRoundTripInt224Boundary() external pure {
        uint256[4] memory values = [uint256(2 ** 223 - 1), 2 ** 223, 2 ** 223 + 1, 2 ** 223 * 10];
        for (uint256 i = 0; i < values.length; i++) {
            for (uint256 j = 0; j < 4; j++) {
                checkFixedDecimalRoundTrip(values[i], j < 2 ? 0 : 104, j % 2 == 1, true);
                checkFixedDecimalRoundTrip(values[i], j < 2 ? 0 : 104, j % 2 == 1, false);
            }
        }
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

    function formatExternal(Float float, bool scientific) external pure returns (string memory) {
        return LibFormatDecimalFloat.toDecimalString(float, scientific);
    }

    /// `float` formats as the oracle renders its parts, and the parser reads
    /// that string back as exactly the same value.
    function checkFormatRoundTrip(Float float, bool scientific) internal pure {
        (int256 c, int256 e) = LibDecimalFloat.unpack(float);
        string memory formatted = LibFormatDecimalFloat.toDecimalString(float, scientific);
        assertEq(formatted, expectedFormat(c, e, scientific), "Formatted value mismatch");
        (bytes4 err, Float parsed) = LibParseDecimalFloat.parseDecimalFloat(formatted);
        assertEq(err, bytes4(0), string.concat("Parse error on: ", formatted));
        (int256 pc, int256 pe) = LibDecimalFloat.unpack(parsed);
        assertEq(LibExactFloat.cmpParts(c, e, pc, pe), 0, string.concat("Round trip mismatch on: ", formatted));
    }

    /// Fuzz: every Float formats in scientific mode.
    function testFormatEveryFloatScientific(bytes32 raw) external pure {
        checkFormatRoundTrip(Float.wrap(raw), true);
    }

    /// Fuzz: every Float formats in non-scientific mode, except a nonzero
    /// value past `MAX_NON_SCIENTIFIC_EXPONENT`, which reverts.
    function testFormatEveryFloatNonScientific(bytes32 raw) external {
        Float float = Float.wrap(raw);
        (int256 c, int256 e) = LibDecimalFloat.unpack(float);
        int256 cap = LibFormatDecimalFloat.MAX_NON_SCIENTIFIC_EXPONENT;
        if (c != 0 && (e > cap || e < -cap)) {
            vm.expectRevert(abi.encodeWithSelector(UnformatableExponent.selector, e));
            this.formatExternal(float, false);
            return;
        }
        checkFormatRoundTrip(float, false);
    }

    /// Fuzz: every coefficient with an exponent inside the cap formats in
    /// non-scientific mode, which a raw Float rarely lands on.
    function testFormatEveryFloatNonScientificInsideCap(int224 coefficient, int256 exponent) external pure {
        int256 cap = LibFormatDecimalFloat.MAX_NON_SCIENTIFIC_EXPONENT;
        exponent = bound(exponent, -cap, cap);
        checkFormatRoundTrip(LibDecimalFloat.packLossless(coefficient, exponent), false);
    }

    /// The extreme Floats format in scientific mode and are past the cap in
    /// non-scientific mode.
    function testFormatExtremeFloats() external {
        Float[4] memory floats = [
            LibDecimalFloat.FLOAT_MAX_POSITIVE_VALUE,
            LibDecimalFloat.FLOAT_MIN_NEGATIVE_VALUE,
            LibDecimalFloat.FLOAT_MIN_POSITIVE_VALUE,
            LibDecimalFloat.FLOAT_MAX_NEGATIVE_VALUE
        ];
        string[4] memory expected = [
            "1.3479973333575319897333507543509815336818572211270286240551805124607e2147483714",
            "-1.3479973333575319897333507543509815336818572211270286240551805124608e2147483714",
            "1e-2147483648",
            "-1e-2147483648"
        ];
        for (uint256 i = 0; i < floats.length; i++) {
            assertEq(LibFormatDecimalFloat.toDecimalString(floats[i], true), expected[i]);
            checkFormatRoundTrip(floats[i], true);
            (, int256 e) = LibDecimalFloat.unpack(floats[i]);
            vm.expectRevert(abi.encodeWithSelector(UnformatableExponent.selector, e));
            this.formatExternal(floats[i], false);
        }
    }

    /// The leading digit's exponent past int32 is printed in full.
    function testFormatScientificExponentPastInt32() external pure {
        Float float = LibDecimalFloat.packLossless(15, type(int32).max);
        assertEq(LibFormatDecimalFloat.toDecimalString(float, true), "1.5e2147483648");
        checkFormatRoundTrip(float, true);
        float = LibDecimalFloat.packLossless(10, type(int32).max);
        assertEq(LibFormatDecimalFloat.toDecimalString(float, true), "1e2147483648");
        checkFormatRoundTrip(float, true);
    }

    /// (1, int32.max) maximizes to 1e76 with the exponent 76 lower, so the
    /// display exponent is int32.max.
    function testFormatScientificExponentAtInt32Max() external pure {
        Float float = LibDecimalFloat.packLossless(1, int256(type(int32).max));
        string memory s = LibFormatDecimalFloat.toDecimalString(float, true);
        assertEq(s, string.concat("1e", Strings.toStringSigned(int256(type(int32).max))));
    }

    /// An integer past int224 formats in non-scientific mode.
    function testFormatNonScientificIntegerPastInt224() external pure {
        Float float = LibDecimalFloat.packLossless(1, 70);
        assertEq(LibFormatDecimalFloat.toDecimalString(float, false), string.concat("1", zeros(70)));
        checkFormatRoundTrip(float, false);
        assertEq(LibFormatDecimalFloat.toDecimalString(float, true), "1e70");
        checkFormatRoundTrip(float, true);
        checkFormatRoundTrip(LibDecimalFloat.packLossless(1, 68), false);
        checkFormatRoundTrip(LibDecimalFloat.packLossless(1, 77), false);
        checkFormatRoundTrip(LibDecimalFloat.packLossless(type(int224).max, 10), false);
        checkFormatRoundTrip(LibDecimalFloat.packLossless(type(int224).min, 10), false);
    }

    /// Both sides of the non-scientific cap at `±MAX_NON_SCIENTIFIC_EXPONENT`
    /// format; one past each reverts in the tests below.
    function testFormatNonScientificCapBoundaries() external pure {
        int256 cap = LibFormatDecimalFloat.MAX_NON_SCIENTIFIC_EXPONENT;
        Float float = LibDecimalFloat.packLossless(1, cap);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(LibFormatDecimalFloat.toDecimalString(float, false), string.concat("1", zeros(uint256(cap))));
        checkFormatRoundTrip(float, false);
        checkFormatRoundTrip(LibDecimalFloat.packLossless(type(int224).min, cap), false);
        float = LibDecimalFloat.packLossless(1, -cap);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(LibFormatDecimalFloat.toDecimalString(float, false), string.concat("0.", zeros(uint256(cap - 1)), "1"));
        checkFormatRoundTrip(float, false);
        checkFormatRoundTrip(LibDecimalFloat.packLossless(type(int224).min, -cap), false);
    }

    /// Fuzz: scientific format over every int224 coefficient and int32
    /// exponent renders as the oracle and round-trips.
    function testFormatParseRoundTripScientificFullDomain(int224 coefficient, int32 exponent) external pure {
        checkFormatRoundTrip(LibDecimalFloat.packLossless(coefficient, exponent), true);
    }

    /// The most digits at the lowest exponents.
    function testFormatScientificNegativeBoundary() external pure {
        checkFormatRoundTrip(LibDecimalFloat.packLossless(type(int224).max, type(int32).min), true);
        checkFormatRoundTrip(LibDecimalFloat.packLossless(type(int224).min, type(int32).min), true);
    }

    /// `float` formats as the oracle renders its own coefficient and exponent.
    function assertFormatsAsOracle(Float float, bool scientific) internal pure {
        (int256 c, int256 e) = LibDecimalFloat.unpack(float);
        assertEq(LibFormatDecimalFloat.toDecimalString(float, scientific), expectedFormat(c, e, scientific));
    }

    /// The largest s with c 10^s in int224 and e - s >= int32.min, for c
    /// nonzero.
    function maxShift(int256 c, int256 e) internal pure returns (uint256 s) {
        int256 limit = c < 0 ? int256(type(int224).min) : int256(type(int224).max);
        while (e > type(int32).min && (c < 0 ? c >= limit / 10 : c <= limit / 10)) {
            c *= 10;
            e -= 1;
            s++;
        }
    }

    /// `float` formats as the oracle renders `c × 10^e`, or non-scientific
    /// past the cap on its own exponent reverts.
    function assertFormatsAs(Float float, int256 c, int256 e, bool scientific) internal {
        (, int256 exponent) = LibDecimalFloat.unpack(float);
        int256 cap = LibFormatDecimalFloat.MAX_NON_SCIENTIFIC_EXPONENT;
        if (!scientific && (exponent > cap || exponent < -cap)) {
            vm.expectRevert(abi.encodeWithSelector(UnformatableExponent.selector, exponent));
            this.formatExternal(float, false);
            return;
        }
        assertEq(LibFormatDecimalFloat.toDecimalString(float, scientific), expectedFormat(c, e, scientific));
    }

    /// Two representations of `base × 10^exponent`, the second with the
    /// coefficient shifted up by `shift` digits, format to the same string.
    function checkCanonicalAcrossRepresentations(int224 base, int256 exponent, uint256 shift, bool scientific)
        internal
    {
        vm.assume(base != 0);
        uint256 maxS = maxShift(base, exponent);
        shift = bound(shift, maxS == 0 ? 0 : 1, maxS);
        // Safe: base 10^shift fits int224, so 10^shift is at most 10^67.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 scaled = int256(base) * int256(10 ** shift);
        Float a = LibDecimalFloat.packLossless(base, exponent);
        // Safe: shift <= 67.
        // forge-lint: disable-next-line(unsafe-typecast)
        Float b = LibDecimalFloat.packLossless(scaled, exponent - int256(shift));
        assertFormatsAs(a, base, exponent, scientific);
        assertFormatsAs(b, base, exponent, scientific);
    }

    /// Fuzz: two representations of the same numeric value format to identical
    /// strings. Covers the formatter's canonicalization behavior (trailing
    /// zeros in coefficient vs expressed via exponent) without going through
    /// the parser. Every nonzero int224 at every int32 exponent, with every
    /// shift that leaves another Float, in both modes.
    function testFormatCanonicalAcrossRepresentations(int224 base, int32 exponent, uint256 shift, bool scientific)
        external
    {
        checkCanonicalAcrossRepresentations(base, exponent, shift, scientific);
    }

    /// The same at a base with room to shift, at least one digit short of
    /// int224 and above the exponent floor, by a shift of at least one, so
    /// the two representations differ. Non-scientific takes base exponents
    /// inside the cap.
    function testFormatCanonicalAcrossRepresentationsShifted(
        int224 base,
        uint256 drop,
        int256 exponent,
        uint256 shift,
        bool scientific
    ) external {
        // A magnitude of at least two digits, divided by at most its digit
        // count less one, stays non-zero, so no input is rejected (#448).
        // Safe: int224.max fits int256 and uint256.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 magnitude =
            bound(uint256(int256(base < 0 ? -int256(base) : int256(base))), 10, uint256(int256(type(int224).max)));
        uint256 digits = 0;
        for (uint256 rest = magnitude; rest > 0; rest /= 10) {
            digits++;
        }
        magnitude /= 10 ** bound(drop, 1, digits - 1);
        // Safe: magnitude is below int224.max.
        // forge-lint: disable-next-line(unsafe-typecast)
        base = int224(base < 0 ? -int256(magnitude) : int256(magnitude));
        int256 cap = LibFormatDecimalFloat.MAX_NON_SCIENTIFIC_EXPONENT;
        exponent =
            scientific ? bound(exponent, int256(type(int32).min) + 1, type(int32).max) : bound(exponent, -cap, cap);
        assertGe(maxShift(base, exponent), 1, "room to shift");
        checkCanonicalAcrossRepresentations(base, exponent, shift, scientific);
    }

    /// Non-scientific mode reverts past the exponent cap, which is most of
    /// int32, so this samples the base exponents it formats.
    function testFormatCanonicalAcrossRepresentationsInsideCap(int224 base, int256 exponent, uint256 shift) external {
        int256 cap = LibFormatDecimalFloat.MAX_NON_SCIENTIFIC_EXPONENT;
        checkCanonicalAcrossRepresentations(base, bound(exponent, -cap, cap), shift, false);
    }

    function testFormatNonScientificExponentAtNegativeCap() external pure {
        int256 cap = LibFormatDecimalFloat.MAX_NON_SCIENTIFIC_EXPONENT;
        Float float = LibDecimalFloat.packLossless(1, -cap);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(LibFormatDecimalFloat.toDecimalString(float, false), string.concat("0.", zeros(uint256(cap - 1)), "1"));
    }

    /// Non-scientific format on the int224 signed range boundaries.
    function testFormatNonScientificInt224MaxCoefficient() external pure {
        Float float = LibDecimalFloat.packLossless(int256(type(int224).max), 0);
        string memory s = LibFormatDecimalFloat.toDecimalString(float, false);
        assertEq(s, Strings.toString(uint256(int256(type(int224).max))));
    }

    function testFormatNonScientificInt224MinCoefficient() external pure {
        Float float = LibDecimalFloat.packLossless(int256(type(int224).min), 0);
        string memory s = LibFormatDecimalFloat.toDecimalString(float, false);
        // int224.min negated fits uint256 (= 2^223).
        assertEq(s, string.concat("-", Strings.toString(uint256(-int256(type(int224).min)))));
    }

    /// `_toNonScientific` branch coverage: effective exponent ends up exactly
    /// at zero after trailing-zero stripping. Exercises the `effExp >= 0`
    /// path with `uEffExp = 0`.
    function testFormatNonScientificEffExpZero() external pure {
        // (100, -2) has trailingZeros=2, sigK=1, effExp=0 → output "1".
        checkFormat(100, -2, false, "1");
        // (12340000, -4) → trailingZeros=4, sigK=4, effExp=0 → "1234".
        checkFormat(12340000, -4, false, "1234");
    }

    /// `_toNonScientific` branch coverage: sigK == absEffExp, decimal point
    /// lands exactly at the start of the significant digits.
    function testFormatNonScientificDecimalAtStart() external pure {
        // (123, -3) → sigK=3, absEffExp=3, so output = "0." + 0 leading zeros + "123".
        checkFormat(123, -3, false, "0.123");
        // Negative variant.
        checkFormat(-123, -3, false, "-0.123");
    }

    /// `_toNonScientific` branch coverage: decimal point in the middle of the
    /// significant digits.
    function testFormatNonScientificDecimalInside() external pure {
        // (12345, -2) → sigK=5, absEffExp=2, splitAt=3. Output "123.45".
        checkFormat(12345, -2, false, "123.45");
        checkFormat(-12345, -2, false, "-123.45");
    }

    /// `_toNonScientific` branch coverage: leading zeros after "0." (sigK <
    /// absEffExp). This is the #182 shape.
    function testFormatNonScientificLeadingZeros() external pure {
        // (5, -5) → sigK=1, absEffExp=5, leadingZeros=4. Output "0.00005".
        checkFormat(5, -5, false, "0.00005");
        checkFormat(-5, -5, false, "-0.00005");
    }

    /// `1e67` non-scientific is `1` and 67 zeros.
    function testFormatNonScientificAtIntDigitBoundary() external pure {
        Float float = LibDecimalFloat.packLossless(1, 67);
        assertEq(LibFormatDecimalFloat.toDecimalString(float, false), string.concat("1", zeros(67)));
        checkFormatRoundTrip(float, false);
    }

    /// For every positive exponent below 68 the largest coefficient whose
    /// integer `|c| × 10^e` fits int224 formats as the oracle renders it, at
    /// both signs.
    function testFormatNonScientificPositiveExponentBoundary() external pure {
        uint256 max = uint256(int256(type(int224).max));
        for (uint256 e = 1; e < 68; e++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 c = int256(max / 10 ** e);
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 exponent = int256(e);
            assertEq(
                LibFormatDecimalFloat.toDecimalString(LibDecimalFloat.packLossless(c, exponent), false),
                expectedFormat(c, exponent, false)
            );
            assertEq(
                LibFormatDecimalFloat.toDecimalString(LibDecimalFloat.packLossless(-c, exponent), false),
                expectedFormat(-c, exponent, false)
            );
        }
    }

    /// `digits` (no trailing zero) shifted right by `fractionDigits` places.
    function placeDecimalPoint(string memory digits, uint256 fractionDigits) internal pure returns (string memory) {
        bytes memory d = bytes(digits);
        if (fractionDigits == 0) {
            return digits;
        }
        if (fractionDigits < d.length) {
            bytes memory integral = new bytes(d.length - fractionDigits);
            bytes memory fraction = new bytes(fractionDigits);
            for (uint256 i = 0; i < d.length; i++) {
                if (i < integral.length) {
                    integral[i] = d[i];
                } else {
                    fraction[i - integral.length] = d[i];
                }
            }
            return string.concat(string(integral), ".", string(fraction));
        }
        return string.concat("0.", zeros(fractionDigits - d.length), digits);
    }

    /// The most negative coefficient formats as `-` and the digits of 2^223.
    function testFormatNonScientificInt224Min() external pure {
        assertEq(
            LibFormatDecimalFloat.toDecimalString(LibDecimalFloat.packLossless(type(int224).min, -3), false),
            "-13479973333575319897333507543509815336818572211270286240551805124.608"
        );
    }

    /// Constants format as expected in both modes.
    function testFormatDecimalFloatConstants() external pure {
        assertEq(LibFormatDecimalFloat.toDecimalString(LibDecimalFloat.FLOAT_ZERO, true), "0");
        assertEq(LibFormatDecimalFloat.toDecimalString(LibDecimalFloat.FLOAT_ZERO, false), "0");
        assertEq(LibFormatDecimalFloat.toDecimalString(LibDecimalFloat.FLOAT_ONE, true), "1");
        assertEq(LibFormatDecimalFloat.toDecimalString(LibDecimalFloat.FLOAT_ONE, false), "1");
        assertEq(LibFormatDecimalFloat.toDecimalString(LibDecimalFloat.FLOAT_HALF, true), "5e-1");
        assertEq(LibFormatDecimalFloat.toDecimalString(LibDecimalFloat.FLOAT_HALF, false), "0.5");
    }

    /// Non-scientific format reverts when `|exponent|` exceeds the policy cap.
    function testFormatNonScientificExponentAboveCapReverts() external {
        int256 exp = LibFormatDecimalFloat.MAX_NON_SCIENTIFIC_EXPONENT + 1;
        Float float = LibDecimalFloat.packLossless(1, exp);
        vm.expectRevert(abi.encodeWithSelector(UnformatableExponent.selector, exp));
        this.formatExternal(float, false);
    }

    function testFormatNonScientificExponentBelowCapReverts() external {
        int256 exp = -LibFormatDecimalFloat.MAX_NON_SCIENTIFIC_EXPONENT - 1;
        Float float = LibDecimalFloat.packLossless(1, exp);
        vm.expectRevert(abi.encodeWithSelector(UnformatableExponent.selector, exp));
        this.formatExternal(float, false);
    }

    /// The exact #182 reproduction: `add` of two near-cancelling values
    /// produces a Float with exponent -77. The non-scientific formatter must
    /// render this without reverting.
    function testFormatNonScientificIssue182Reproduction() external pure {
        Float net = LibDecimalFloat.packLossless(-9999999910959448, -17);
        Float fill = LibDecimalFloat.packLossless(99999999, -9);
        Float result = net.add(fill);
        // Numeric value is -1.0959448e-10.
        string memory formatted = result.toDecimalString(false);
        assertEq(formatted, "-0.00000000010959448");
    }
}
