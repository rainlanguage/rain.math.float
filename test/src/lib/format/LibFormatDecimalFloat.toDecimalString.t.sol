// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std/Test.sol";
import {Float, LibDecimalFloat} from "src/lib/LibDecimalFloat.sol";
import {LibFormatDecimalFloat} from "src/lib/format/LibFormatDecimalFloat.sol";
import {LibParseDecimalFloat} from "src/lib/parse/LibParseDecimalFloat.sol";
import {UnformatableExponent} from "src/error/ErrFormat.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

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

    function formatExternal(Float float, bool scientific) external pure returns (string memory) {
        return LibFormatDecimalFloat.toDecimalString(float, scientific);
    }

    /// Fuzz: every Float round-trips through scientific format → parse → eq
    /// across the full int224 coefficient domain, with exponent bounded to
    /// leave headroom for the scientific display exponent.
    ///
    /// Scientific format renders `coef × 10^exp` as `d.dddd × 10^displayExp`
    /// where `displayExp = exp + 75 or 76` (after `maximizeFull` + scale).
    /// For exponents within ~76 of `int32.max`, the resulting display exponent
    /// exceeds `int32.max`, and the parser rejects it on re-pack. The
    /// headroom below avoids that asymmetric range; see separate issue for
    /// the format/parse exponent-range mismatch.
    function testFormatParseRoundTripScientificFullDomain(int224 coefficient, int32 exponent) external pure {
        int256 headroom = 80;
        // `bound` to a sub-range of int32 that avoids display-exponent overflow.
        // forge-lint: disable-next-line(unsafe-typecast)
        exponent = int32(bound(exponent, int256(type(int32).min) + headroom, int256(type(int32).max) - headroom));
        _checkRoundTrip(coefficient, exponent, true);
    }

    /// Fuzz: every Float with non-positive exponent round-trips through
    /// non-scientific format → parse → eq, across the full int224 coefficient
    /// domain and exponent in `[-MAX_NON_SCIENTIFIC_EXPONENT, 0]`.
    ///
    /// Positive exponents are NOT fuzzed here: the non-scientific formatter
    /// emits `coefficient_digits + exponent` trailing zeros, which can exceed
    /// the parser's int256 accumulator for modest positive exponents with
    /// non-trivial coefficients. That format/parse asymmetry is a separate
    /// concern (see issue for tracking); this fuzz covers the negative-exp
    /// range where #182-class bugs surface.
    function testFormatParseRoundTripNonScientificNegExpFullDomain(int224 coefficient, int32 exponent) external pure {
        int256 cap = LibFormatDecimalFloat.MAX_NON_SCIENTIFIC_EXPONENT;
        // `bound` returns a value in [-cap, 0]; cap fits int32 so the cast back
        // cannot truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        exponent = int32(bound(exponent, -cap, 0));
        _checkRoundTrip(coefficient, exponent, false);
    }

    function _checkRoundTrip(int256 coefficient, int256 exponent, bool scientific) internal pure {
        Float original = LibDecimalFloat.packLossless(coefficient, exponent);
        string memory formatted = LibFormatDecimalFloat.toDecimalString(original, scientific);
        (bytes4 err, Float parsed) = LibParseDecimalFloat.parseDecimalFloat(formatted);
        assertEq(err, bytes4(0), string.concat("Parse error on: ", formatted));
        assertTrue(original.eq(parsed), string.concat("Round trip mismatch on: ", formatted));
        string memory reFormatted = LibFormatDecimalFloat.toDecimalString(parsed, scientific);
        assertEq(formatted, reFormatted, "Formatting not canonical");
    }

    /// Fuzz: two representations of the same numeric value format to identical
    /// strings. Covers the formatter's canonicalization behavior (trailing
    /// zeros in coefficient vs expressed via exponent) without going through
    /// the parser. Runs for both scientific and non-scientific modes,
    /// including the full non-scientific positive-exp range that the
    /// round-trip fuzz cannot cover (see #184).
    function testFormatCanonicalAcrossRepresentations(int128 base, uint8 shift, bool scientific) external pure {
        vm.assume(base != 0);
        int256 baseInt = int256(base);
        int256 absBase = baseInt < 0 ? -baseInt : baseInt;

        // Find the largest shift `s` such that `absBase * 10^s` fits int224.
        uint256 maxShift = 0;
        int256 scale = 1;
        while (scale <= type(int224).max / 10 / absBase) {
            scale *= 10;
            maxShift++;
        }
        if (maxShift == 0) return;

        uint256 s = bound(shift, 1, maxShift);
        int256 scaled = baseInt * int256(10 ** s);

        // Exponent pair chosen so both representations are well inside int32.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 baseExp = scientific ? int256(0) : -int256(s);

        Float a = LibDecimalFloat.packLossless(baseInt, baseExp);
        // forge-lint: disable-next-line(unsafe-typecast)
        Float b = LibDecimalFloat.packLossless(scaled, baseExp - int256(s));
        assertTrue(a.eq(b), "precondition: representations should be equal");

        string memory formatA = LibFormatDecimalFloat.toDecimalString(a, scientific);
        string memory formatB = LibFormatDecimalFloat.toDecimalString(b, scientific);
        assertEq(formatA, formatB, "Different representations formatted to different strings");
    }

    /// Non-scientific format succeeds at the exact cap boundary.
    function testFormatNonScientificExponentAtPositiveCap() external pure {
        int256 cap = LibFormatDecimalFloat.MAX_NON_SCIENTIFIC_EXPONENT;
        Float float = LibDecimalFloat.packLossless(1, cap);
        string memory s = LibFormatDecimalFloat.toDecimalString(float, false);
        // "1" followed by `cap` zeros.
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(bytes(s).length, 1 + uint256(cap));
        assertEq(bytes(s)[0], bytes1("1"));
    }

    function testFormatNonScientificExponentAtNegativeCap() external pure {
        int256 cap = LibFormatDecimalFloat.MAX_NON_SCIENTIFIC_EXPONENT;
        Float float = LibDecimalFloat.packLossless(1, -cap);
        string memory s = LibFormatDecimalFloat.toDecimalString(float, false);
        // "0." + (cap - 1) leading zeros + "1".
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(bytes(s).length, 2 + uint256(cap - 1) + 1);
        assertEq(bytes(s)[0], bytes1("0"));
        assertEq(bytes(s)[1], bytes1("."));
        assertEq(bytes(s)[bytes(s).length - 1], bytes1("1"));
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

    /// Fuzz: non-scientific format does not revert for any valid Float with
    /// `|exponent| <= MAX_NON_SCIENTIFIC_EXPONENT`, across the full int224
    /// coefficient range. Covers the positive-exponent sub-range that the
    /// parse round-trip fuzz cannot exercise (blocked on #184).
    function testFormatNonScientificSucceedsAcrossFullRange(int224 coefficient, int32 exponent) external pure {
        int256 cap = LibFormatDecimalFloat.MAX_NON_SCIENTIFIC_EXPONENT;
        // `bound` to [-cap, cap]; cap fits int32 so the cast is safe.
        // forge-lint: disable-next-line(unsafe-typecast)
        exponent = int32(bound(exponent, -cap, cap));
        Float float = LibDecimalFloat.packLossless(coefficient, exponent);
        // Should not revert.
        string memory s = LibFormatDecimalFloat.toDecimalString(float, false);
        // Non-empty output is a minimum sanity guarantee.
        assertGt(bytes(s).length, 0);
    }

    /// Fuzz: output shape properties for non-scientific format.
    /// - Never ends with "." (formatter always strips trailing zeros from the
    ///   fractional part; a lone "." would indicate a bug).
    /// - If the output contains ".", no trailing zeros after it.
    /// - If negative, leading character is "-" and remainder has same shape
    ///   as the positive case.
    function testFormatNonScientificOutputShape(int224 coefficient, int32 exponent) external pure {
        vm.assume(coefficient != 0);
        // int224.min negated exceeds int224.max, so skip it for the
        // negation-symmetry check below.
        vm.assume(coefficient != type(int224).min);
        int256 cap = LibFormatDecimalFloat.MAX_NON_SCIENTIFIC_EXPONENT;
        // forge-lint: disable-next-line(unsafe-typecast)
        exponent = int32(bound(exponent, -cap, cap));
        Float float = LibDecimalFloat.packLossless(coefficient, exponent);
        bytes memory s = bytes(LibFormatDecimalFloat.toDecimalString(float, false));
        assertGt(s.length, 0);

        // Never ends with ".".
        assertNotEq(uint8(s[s.length - 1]), uint8(bytes1(".")));

        // If a "." is present, no trailing zero after it.
        bool hasDot;
        for (uint256 i = 0; i < s.length; i++) {
            if (s[i] == ".") {
                hasDot = true;
                break;
            }
        }
        if (hasDot) {
            assertNotEq(uint8(s[s.length - 1]), uint8(bytes1("0")), "trailing zero after decimal point");
        }

        // Negative outputs start with "-" and have the same shape as the
        // positive counterpart.
        if (coefficient < 0) {
            assertEq(uint8(s[0]), uint8(bytes1("-")));
            Float positive = LibDecimalFloat.packLossless(-int256(coefficient), exponent);
            string memory pos = LibFormatDecimalFloat.toDecimalString(positive, false);
            assertEq(string(s), string.concat("-", pos));
        }
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

    /// Non-scientific format of `(1, 77)` produces "1" followed by 77 zeros.
    /// Historically this reverted because the implementation computed
    /// `10^exponent` as int256; the rewrite uses direct string placement and
    /// handles any `|exponent| <= MAX_NON_SCIENTIFIC_EXPONENT`.
    function testFormatNonScientificLargePositiveExponent() external pure {
        checkFormat(1, 77, false, "100000000000000000000000000000000000000000000000000000000000000000000000000000");
    }

    /// Non-scientific format of a large coefficient with moderate positive
    /// exponent formats without overflow. `int224.max = 2^223 - 1`, which has
    /// 68 decimal digits; with exponent 10 the output is 78 characters.
    function testFormatNonScientificLargeCoefficientLargeExponent() external pure {
        int256 c = int256(type(int224).max);
        string memory expected = string.concat(Strings.toStringSigned(c), "0000000000");
        checkFormat(c, 10, false, expected);
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
