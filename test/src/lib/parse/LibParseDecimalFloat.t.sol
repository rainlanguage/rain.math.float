// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {LibParseDecimalFloat} from "../../../../src/lib/parse/LibParseDecimalFloat.sol";
import {LibBytes, Pointer} from "rain-solmem-0.1.28/src/lib/LibBytes.sol";
import {Strings} from "@openzeppelin-contracts-5.7.0/utils/Strings.sol";
import {ParseEmptyDecimalString} from "rain-string-0.3.9/src/error/ErrParse.sol";
import {
    MalformedExponentDigits,
    ParseDecimalPrecisionLoss,
    MalformedDecimalPoint,
    ParseDecimalFloatExcessCharacters
} from "../../../../src/error/ErrParse.sol";
import {ExponentOverflow} from "../../../../src/error/ErrDecimalFloat.sol";
import {Float, LibDecimalFloat} from "../../../../src/lib/LibDecimalFloat.sol";
import {LibTestDecimalLiteral, Literal} from "../../../lib/LibTestDecimalLiteral.sol";
import {LibExactFloat} from "../../../lib/LibExactFloat.sol";
import {LibTestDecimalLiteral} from "../../../lib/LibTestDecimalLiteral.sol";

contract LibParseDecimalFloatTest is Test {
    using LibBytes for bytes;
    using Strings for uint256;
    using LibDecimalFloat for Float;

    function parseDecimalFloatInlineExternal(string memory data)
        external
        pure
        returns (bytes4 errorSelector, uint256 cursorAfter, int256 signedCoefficient, int256 exponent)
    {
        uint256 cursor = Pointer.unwrap(bytes(data).dataPointer());
        uint256 start = cursor;
        (errorSelector, cursorAfter, signedCoefficient, exponent) =
            LibParseDecimalFloat.parseDecimalFloatInline(cursor, Pointer.unwrap(bytes(data).endDataPointer()));
        // Pragmatically the length of the inline movement is more useful than
        // the raw cursor because the external function has different memory
        // positions than the caller.
        cursorAfter -= start;
    }

    function parseDecimalFloatExternal(string memory data) external pure returns (bytes4 errorSelector, Float float) {
        (errorSelector, float) = LibParseDecimalFloat.parseDecimalFloat(data);
    }

    /// A return and a revert are tagged apart, so equal outcomes are equal bytes.
    function parseOutcome(string memory s) internal view returns (bytes memory) {
        try this.parseDecimalFloatExternal(s) returns (bytes4 err, Float float) {
            return abi.encode("return", err, float);
        } catch (bytes memory revertData) {
            return abi.encode("revert", revertData);
        }
    }

    /// Both entry points against the literal's exact value and the documented
    /// rule, read by `LibTestDecimalLiteral` independently of the library.
    function checkAgainstRule(string memory data) internal view {
        Literal memory lit = LibTestDecimalLiteral.read(bytes(data));
        bool isFloat = LibTestDecimalLiteral.isFloat(lit);
        bool isPast = LibTestDecimalLiteral.isPast(lit);
        bytes4 valueError =
            isPast ? ExponentOverflow.selector : (isFloat ? bytes4(0) : ParseDecimalPrecisionLoss.selector);

        (bytes4 err, uint256 cursor, int256 c, int256 e) = this.parseDecimalFloatInlineExternal(data);
        assertEq(cursor, lit.cursor, "inline cursor");
        if (lit.malformed != 0) {
            assertEq(err, lit.malformed, "inline malformed");
        } else if (isPast) {
            assertEq(err, ExponentOverflow.selector, "inline overflow");
        } else if (err == 0) {
            assertTrue(LibTestDecimalLiteral.isValue(lit, c, e), "inline value");
        } else {
            assertEq(err, valueError, "inline value error");
        }
        if (err != 0) {
            assertEq(c, 0, "inline error coefficient");
            assertEq(e, 0, "inline error exponent");
        }

        bytes4 expected = lit.malformed != 0
            ? lit.malformed
            : (lit.cursor != bytes(data).length ? ParseDecimalFloatExcessCharacters.selector : valueError);
        (bytes4 packedErr, Float float) = this.parseDecimalFloatExternal(data);
        assertEq(packedErr, expected, "error");
        if (packedErr == 0) {
            (int256 packedC, int256 packedE) = float.unpack();
            assertTrue(LibTestDecimalLiteral.isValue(lit, packedC, packedE), "value");
        } else {
            assertEq(Float.unwrap(float), bytes32(0), "error float");
        }
    }

    /// Any int256 at an exponent around the overflow threshold, written plain
    /// and with 80 leading zeros, which takes the past-int256 path, against
    /// the rule. Every value at or past the threshold returns
    /// `ExponentOverflow` from both entry points, never a revert (#510).
    function testParseNearOverflowThreshold(int256 c, uint256 offset) external view {
        int256 e = int256(type(int32).max) - 12 + int256(bound(offset, 0, 84));
        string memory exponent = string.concat("e", Strings.toStringSigned(e));
        string memory digits = Strings.toString(LibExactFloat.abs(c));
        string memory sign = c < 0 ? "-" : "";
        checkAgainstRule(string.concat(sign, digits, exponent));
        checkAgainstRule(string.concat(sign, LibTestDecimalLiteral.zeroString(80), digits, exponent));
    }

    /// The threshold from either side at every excess the check branches on:
    /// `(2^223 + 2) × 10^int32.max` written as `m × 10^(int32.max + x)`, and
    /// one unit of the last digit below it.
    function testParseOverflowThresholdExcesses() external view {
        uint256 threshold = 2 ** 223 + 2;
        int256 int32Max = int256(type(int32).max);
        // Below the threshold, 2^223 + 1 is past the largest Float of either
        // sign but packs lossily.
        uint256 m = threshold;
        for (int256 x = 0; x >= -9; x--) {
            if (x < 0) {
                m *= 10;
            }
            checkThresholdSides(m, int32Max + x, ExponentOverflow.selector);
            checkThresholdSides(m - 1, int32Max + x, ParseDecimalPrecisionLoss.selector);
        }
        // Positive excesses: the smallest coefficient at or past it is
        // ceil(threshold / 10^x), and one below is exactly a Float or a lossy
        // pack.
        uint256 scale = 1;
        for (int256 x = 1; x <= 67; x++) {
            scale *= 10;
            m = (threshold + scale - 1) / scale;
            checkThresholdSides(m, int32Max + x, ExponentOverflow.selector);
            if (m > 1) {
                string memory below = string.concat((m - 1).toString(), "e", Strings.toStringSigned(int32Max + x));
                checkAgainstRule(below);
                (bytes4 err,) = this.parseDecimalFloatExternal(below);
                assertTrue(err != ExponentOverflow.selector, "below overflows");
            }
        }
        checkThresholdSides(1, int32Max + 68, ExponentOverflow.selector);
        checkThresholdSides(1, int32Max + 67, bytes4(0));
    }

    function checkThresholdSides(uint256 m, int256 e, bytes4 expected) internal view {
        string memory s = string.concat(m.toString(), "e", Strings.toStringSigned(e));
        string[2] memory literals = [s, string.concat("-", s)];
        for (uint256 i = 0; i < literals.length; i++) {
            checkAgainstRule(literals[i]);
            (bytes4 err, Float float) = this.parseDecimalFloatExternal(literals[i]);
            assertEq(err, expected, literals[i]);
            if (expected != 0) {
                assertEq(Float.unwrap(float), bytes32(0), "error float");
            }
        }
    }

    /// Any string, against the rule.
    function testParsePacked(string memory data) external view {
        checkAgainstRule(data);
    }

    function checkParseDecimalFloat(
        string memory data,
        int256 expectedSignedCoefficient,
        int256 expectedExponent,
        uint256 expectedCursorAfter
    ) internal pure {
        uint256 cursor = Pointer.unwrap(bytes(data).dataPointer());
        (bytes4 errorSelector, uint256 cursorAfter, int256 signedCoefficient, int256 exponent) =
            LibParseDecimalFloat.parseDecimalFloatInline(cursor, Pointer.unwrap(bytes(data).endDataPointer()));
        assertEq(errorSelector, bytes4(0));
        assertEq(signedCoefficient, expectedSignedCoefficient);
        assertEq(exponent, expectedExponent);
        assertEq(cursorAfter - cursor, expectedCursorAfter);
    }

    function checkParseDecimalFloatFail(string memory data, bytes4 expectedErrorSelector, uint256 expectedCursorAfter)
        internal
        pure
    {
        uint256 cursor = Pointer.unwrap(bytes(data).dataPointer());
        (bytes4 errorSelector, uint256 cursorAfter,,) =
            LibParseDecimalFloat.parseDecimalFloatInline(cursor, Pointer.unwrap(bytes(data).endDataPointer()));
        assertEq(errorSelector, expectedErrorSelector);
        assertEq(cursorAfter - cursor, expectedCursorAfter);
    }

    /// Fuzz every uint256 integer literal, either sign, with leading zeros.
    /// Within int256 of its sign it parses to itself at exponent 0. Past it,
    /// the trailing zeros move to the exponent, and significant digits still
    /// past int256 are no Float, `ParseDecimalPrecisionLoss`.
    function testParseLiteralDecimalFloatFuzz(uint256 value, uint8 leadingZerosCount, bool isNeg) external pure {
        string memory str = value.toString();

        string memory leadingZeros = new string(leadingZerosCount);
        for (uint8 i = 0; i < leadingZerosCount; i++) {
            bytes(leadingZeros)[i] = "0";
        }

        string memory input = string(abi.encodePacked((isNeg ? "-" : ""), leadingZeros, str));

        uint256 limit = isNeg ? uint256(type(int256).max) + 1 : uint256(type(int256).max);
        uint256 significand = value;
        int256 exponent = 0;
        if (value > limit) {
            while (significand % 10 == 0) {
                significand /= 10;
                exponent++;
            }
        }
        if (significand > limit) {
            checkParseDecimalFloatFail(input, ParseDecimalPrecisionLoss.selector, bytes(input).length);
            return;
        }
        int256 expected;
        if (significand == uint256(type(int256).max) + 1) {
            expected = type(int256).min;
        } else {
            // significand is at most int256.max here.
            // forge-lint: disable-next-line(unsafe-typecast)
            expected = isNeg ? -int256(significand) : int256(significand);
        }
        checkParseDecimalFloat(input, expected, exponent, bytes(input).length);
    }

    /// Check some specific examples.
    function testParseLiteralDecimalFloatSpecific() external pure {
        checkParseDecimalFloat("0", 0, 0, 1);
        checkParseDecimalFloat("1", 1, 0, 1);
        checkParseDecimalFloat("10", 10, 0, 2);
        checkParseDecimalFloat("100", 100, 0, 3);
        checkParseDecimalFloat("1000", 1000, 0, 4);
        checkParseDecimalFloat("2", 2, 0, 1);
    }

    /// Check some specific examples with leading zeros.
    function testParseLiteralDecimalFloatLeadingZeros() external pure {
        checkParseDecimalFloat("0000", 0, 0, 4);
        checkParseDecimalFloat("0001", 1, 0, 4);
        checkParseDecimalFloat("0010", 10, 0, 4);
        checkParseDecimalFloat("0100", 100, 0, 4);
        checkParseDecimalFloat("1000", 1000, 0, 4);
        checkParseDecimalFloat("0002", 2, 0, 4);
        checkParseDecimalFloat(
            "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001",
            1,
            0,
            128
        );
    }

    /// Check some examples of decimals.
    function testParseLiteralDecimalFloatDecimals() external pure {
        checkParseDecimalFloat("0.1", 1, -1, 3);
        checkParseDecimalFloat("0.01", 1, -2, 4);
        checkParseDecimalFloat("0.001", 1, -3, 5);
        checkParseDecimalFloat("0.0001", 1, -4, 6);
        checkParseDecimalFloat("0.00001", 1, -5, 7);
        checkParseDecimalFloat("0.000001", 1, -6, 8);
        checkParseDecimalFloat("0.0000001", 1, -7, 9);
        checkParseDecimalFloat("0.00000001", 1, -8, 10);
        checkParseDecimalFloat("0.000000001", 1, -9, 11);
        checkParseDecimalFloat("0.0000000001", 1, -10, 12);
        checkParseDecimalFloat("0.00000000001", 1, -11, 13);
        checkParseDecimalFloat("0.000000000001", 1, -12, 14);
        checkParseDecimalFloat("0.0000000000001", 1, -13, 15);
        checkParseDecimalFloat("0.00000000000001", 1, -14, 16);
        checkParseDecimalFloat("0.000000000000001", 1, -15, 17);
        checkParseDecimalFloat("0.0000000000000001", 1, -16, 18);
        checkParseDecimalFloat("0.00000000000000001", 1, -17, 19);
        checkParseDecimalFloat("0.000000000000000001", 1, -18, 20);
        checkParseDecimalFloat("0.0000000000000000001", 1, -19, 21);
        checkParseDecimalFloat("0.00000000000000000001", 1, -20, 22);
        checkParseDecimalFloat("0.000000000000000000001", 1, -21, 23);
        checkParseDecimalFloat("0.0000000000000000000001", 1, -22, 24);
        checkParseDecimalFloat(
            "0.0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001",
            1,
            -127,
            129
        );
        checkParseDecimalFloat(
            "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000.0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001",
            1,
            -127,
            254
        );

        checkParseDecimalFloat("1.1", 11, -1, 3);
        checkParseDecimalFloat("1.01", 101, -2, 4);
        checkParseDecimalFloat("1.001", 1001, -3, 5);
        checkParseDecimalFloat("1.0001", 10001, -4, 6);
        checkParseDecimalFloat("1.0001", 10001, -4, 6);

        checkParseDecimalFloat("10.1", 101, -1, 4);
        checkParseDecimalFloat("10.01", 1001, -2, 5);
        checkParseDecimalFloat("10.001", 10001, -3, 6);
        checkParseDecimalFloat("10.0001", 100001, -4, 7);

        checkParseDecimalFloat("100.1", 1001, -1, 5);
        checkParseDecimalFloat("100.01", 10001, -2, 6);
        // some trailing zeros
        checkParseDecimalFloat("100.001000", 100001, -3, 10);
        checkParseDecimalFloat(
            "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100.0001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
            1000001,
            -4,
            260
        );
    }

    /// Check some examples of exponents.
    function testParseLiteralDecimalFloatExponents() external pure {
        checkParseDecimalFloat("0e0", 0, 0, 3);
        // A capital E.
        checkParseDecimalFloat("0E0", 0, 0, 3);
        checkParseDecimalFloat("0e1", 0, 0, 3);
        checkParseDecimalFloat("0e2", 0, 0, 3);
        checkParseDecimalFloat("0e-1", 0, 0, 4);
        checkParseDecimalFloat("0e-2", 0, 0, 4);

        checkParseDecimalFloat("1e1", 1, 1, 3);
        checkParseDecimalFloat("1e2", 1, 2, 3);
        checkParseDecimalFloat("1e3", 1, 3, 3);
        checkParseDecimalFloat("1e4", 1, 4, 3);
        checkParseDecimalFloat("1e5", 1, 5, 3);
        checkParseDecimalFloat("1e6", 1, 6, 3);
        checkParseDecimalFloat("1e7", 1, 7, 3);
        checkParseDecimalFloat("1e8", 1, 8, 3);
        checkParseDecimalFloat("1e9", 1, 9, 3);
        checkParseDecimalFloat("1e10", 1, 10, 4);
        checkParseDecimalFloat("1e11", 1, 11, 4);
        checkParseDecimalFloat("1e12", 1, 12, 4);
        checkParseDecimalFloat("1e13", 1, 13, 4);
        checkParseDecimalFloat("1e14", 1, 14, 4);
        checkParseDecimalFloat("1e15", 1, 15, 4);
        checkParseDecimalFloat("1e16", 1, 16, 4);
        checkParseDecimalFloat("1e17", 1, 17, 4);
        checkParseDecimalFloat("1e18", 1, 18, 4);
        checkParseDecimalFloat("1e19", 1, 19, 4);
        checkParseDecimalFloat("1e20", 1, 20, 4);
        checkParseDecimalFloat("1e21", 1, 21, 4);
        checkParseDecimalFloat("1e22", 1, 22, 4);
        checkParseDecimalFloat("1e23", 1, 23, 4);
        checkParseDecimalFloat("1e24", 1, 24, 4);
        checkParseDecimalFloat("1e25", 1, 25, 4);
        checkParseDecimalFloat("1e26", 1, 26, 4);
        checkParseDecimalFloat("1e260", 1, 260, 5);

        checkParseDecimalFloat("1e0", 1, 0, 3);
        // A capital E.
        checkParseDecimalFloat("1E0", 1, 0, 3);
        checkParseDecimalFloat("1e-0", 1, 0, 4);
        // A capital E.
        checkParseDecimalFloat("1E-0", 1, 0, 4);

        checkParseDecimalFloat("1e-1", 1, -1, 4);
        checkParseDecimalFloat("1e-2", 1, -2, 4);
        checkParseDecimalFloat("1e-3", 1, -3, 4);
        checkParseDecimalFloat("1e-4", 1, -4, 4);
        checkParseDecimalFloat("1e-5", 1, -5, 4);
        checkParseDecimalFloat("1e-6", 1, -6, 4);
        checkParseDecimalFloat("1e-7", 1, -7, 4);
        checkParseDecimalFloat("1e-8", 1, -8, 4);

        checkParseDecimalFloat("1e-9912873918273981273918273918739182", 1, -9912873918273981273918273918739182, 37);
        // Past the overflow threshold, so ExponentOverflow by value (#510).
        checkParseDecimalFloatFail("1e9912873918273981273918273918739182", ExponentOverflow.selector, 36);
        checkParseDecimalFloatFail(
            "1e57896044618658097711785492504343953926634992332820282019728792003956564819967",
            ExponentOverflow.selector,
            79
        );
        checkParseDecimalFloatFail(
            "57896044618658097711785492504343953926634992332820282019728792003956564819967e57896044618658097711785492504343953926634992332820282019728792003956564819967",
            ExponentOverflow.selector,
            155
        );
        checkParseDecimalFloat(
            "1e-57896044618658097711785492504343953926634992332820282019728792003956564819968", 1, type(int256).min, 80
        );
        checkParseDecimalFloat(
            "-57896044618658097711785492504343953926634992332820282019728792003956564819968e-57896044618658097711785492504343953926634992332820282019728792003956564819968",
            type(int256).min,
            type(int256).min,
            157
        );

        checkParseDecimalFloat("0.0e0", 0, 0, 5);
        checkParseDecimalFloat("0.0e1", 0, 0, 5);
        checkParseDecimalFloat("1.1e1", 11, 0, 5);
        checkParseDecimalFloat("1.1e-1", 11, -2, 6);

        // Some negatives.
        checkParseDecimalFloat("-1.1e-1", -11, -2, 7);
        checkParseDecimalFloat("-10.01e-1", -1001, -3, 9);
        checkParseDecimalFloat("-0.1", -1, -1, 4);
    }

    /// Test some unrelated data after the decimal.
    function testParseLiteralDecimalFloatUnrelated() external pure {
        checkParseDecimalFloat("0.0hello", 0, 0, 3);
        checkParseDecimalFloat("0.0e0hello", 0, 0, 5);
        checkParseDecimalFloat("0.0e1hello", 0, 0, 5);
        checkParseDecimalFloat("1.1e1hello", 11, 0, 5);
        checkParseDecimalFloat("1.1e-1hello", 11, -2, 6);
        checkParseDecimalFloat("-1.1e-1hello", -11, -2, 7);
        checkParseDecimalFloat("1.2.3", 12, -1, 3);
        checkParseDecimalFloat("1.2.3e4", 12, -1, 3);
        checkParseDecimalFloat("-1.2.3", -12, -1, 4);
        checkParseDecimalFloat("1.2e3.4", 12, 2, 5);
    }

    /// issue found in fuzzing round trip with formatter 1.
    function testParseFormatterRoundTripBug0() external pure {
        checkParseDecimalFloat(
            "1.3479973333575319897333507543509815336818572211270286240551805124605e49",
            13479973333575319897333507543509815336818572211270286240551805124605,
            -18,
            72
        );
    }

    /// An empty string should fail.
    function testParseDecimalFloatEmpty() external pure {
        checkParseDecimalFloatFail("", ParseEmptyDecimalString.selector, 0);
    }

    /// A non decimal string should revert.
    function testParseDecimalFloatNonDecimal() external pure {
        checkParseDecimalFloatFail("hello", ParseEmptyDecimalString.selector, 0);
    }

    /// e without a number should revert.
    function testParseDecimalFloatExponentRevert() external pure {
        checkParseDecimalFloatFail("e", ParseEmptyDecimalString.selector, 0);
    }

    /// e with a left digit but not right should revert.
    function testParseDecimalFloatExponentRevert2() external pure {
        checkParseDecimalFloatFail("1e", MalformedExponentDigits.selector, 2);
    }

    /// e with a left digit but not right should revert. Add a negative sign.
    function testParseDecimalFloatExponentRevert3() external pure {
        checkParseDecimalFloatFail("1e-", MalformedExponentDigits.selector, 3);
    }

    /// e with a right digit but not left should revert.
    function testParseDecimalFloatExponentRevert4() external pure {
        checkParseDecimalFloatFail("e1", ParseEmptyDecimalString.selector, 0);
    }

    /// e with a right digit but not left should revert.
    /// two digits.
    function testParseLiteralDecimalFloatExponentRevert5() external pure {
        checkParseDecimalFloatFail("e10", ParseEmptyDecimalString.selector, 0);
    }

    /// e with a right digit but not left should revert.
    /// two digits with negative sign.
    function testParseLiteralDecimalFloatExponentRevert6() external pure {
        checkParseDecimalFloatFail("e-10", ParseEmptyDecimalString.selector, 0);
    }

    /// Dot without digits should revert.
    function testParseLiteralDecimalFloatDotRevert() external pure {
        checkParseDecimalFloatFail(".", ParseEmptyDecimalString.selector, 0);
    }

    /// Dot without leading digits should revert.
    function testParseLiteralDecimalFloatDotRevert2() external pure {
        checkParseDecimalFloatFail(".1", ParseEmptyDecimalString.selector, 0);
    }

    /// Dot without trailing digits should revert.
    function testParseLiteralDecimalFloatDotRevert3() external pure {
        checkParseDecimalFloatFail("1.", MalformedDecimalPoint.selector, 2);
    }

    /// Dot e is an error.
    function testParseLiteralDecimalFloatDotE() external pure {
        checkParseDecimalFloatFail(".e", ParseEmptyDecimalString.selector, 0);
    }

    /// Dot e0 is an error.
    function testParseLiteralDecimalFloatDotE0() external pure {
        checkParseDecimalFloatFail(".e0", ParseEmptyDecimalString.selector, 0);
    }

    /// e dot is an error.
    function testParseLiteralDecimalFloatEDot() external pure {
        checkParseDecimalFloatFail("e.", ParseEmptyDecimalString.selector, 0);
    }

    /// Explicit positive exponent sign is accepted and equivalent to no sign.
    function testParseLiteralDecimalFloatPositiveExponentSign() external pure {
        checkParseDecimalFloat("1e+2", 1, 2, 4);
        checkParseDecimalFloat("1.0e+2", 1, 2, 6);
        checkParseDecimalFloat("1E+2", 1, 2, 4);
        checkParseDecimalFloat("0e+0", 0, 0, 4);
        checkParseDecimalFloat("0e+1", 0, 0, 4);
        checkParseDecimalFloat("1e+0", 1, 0, 4);
        checkParseDecimalFloat("1e+260", 1, 260, 6);
        checkParseDecimalFloat("-1e+2", -1, 2, 5);
        checkParseDecimalFloat("1.1e+1", 11, 0, 6);
    }

    /// Positive sign with no digits is still an error.
    function testParseLiteralDecimalFloatPositiveENoDigits() external pure {
        checkParseDecimalFloatFail("1e+", MalformedExponentDigits.selector, 3);
        checkParseDecimalFloatFail("0.0e+", MalformedExponentDigits.selector, 5);
    }

    /// An exponent takes one sign. A `+` after a `-` must not be skipped, or
    /// `1e-+2` parses as `1e2` with the `-` silently dropped.
    function testParseLiteralDecimalFloatExponentSignAfterNegativeSign() external pure {
        checkParseDecimalFloatFail("1e-+2", MalformedExponentDigits.selector, 3);
    }

    function testParseLiteralDecimalFloatExponentNegativeSignAfterPositiveSign() external pure {
        checkParseDecimalFloatFail("1e+-2", MalformedExponentDigits.selector, 3);
    }

    /// A coefficient takes at most one `-`.
    function testParseLiteralDecimalFloatRepeatedNegativeSign() external pure {
        checkParseDecimalFloatFail("--5", ParseEmptyDecimalString.selector, 1);
        checkParseDecimalFloatFail("---5", ParseEmptyDecimalString.selector, 1);
        checkParseDecimalFloatFail("--5.5e2", ParseEmptyDecimalString.selector, 1);
        checkParseDecimalFloatFail("-.5", ParseEmptyDecimalString.selector, 1);
        checkParseDecimalFloatFail("-", ParseEmptyDecimalString.selector, 1);
        checkParseDecimalFloat("-5", -5, 0, 2);
    }

    /// An exponent takes at most one `-`.
    function testParseLiteralDecimalFloatRepeatedExponentNegativeSign() external pure {
        checkParseDecimalFloatFail("1e--2", MalformedExponentDigits.selector, 3);
        checkParseDecimalFloatFail("1e---2", MalformedExponentDigits.selector, 3);
        checkParseDecimalFloatFail("1.5e--2", MalformedExponentDigits.selector, 5);
        checkParseDecimalFloat("1e-2", 1, -2, 4);
    }

    /// Repeated signs are rejected for any digits that follow them.
    function testParseLiteralDecimalFloatRepeatedNegativeSignFuzz(uint256 value, uint8 extra) external pure {
        string memory digits = value.toString();
        bytes memory dashes = new bytes(uint256(extra) + 2);
        for (uint256 i = 0; i < dashes.length; i++) {
            dashes[i] = "-";
        }
        checkParseDecimalFloatFail(string(abi.encodePacked(dashes, digits)), ParseEmptyDecimalString.selector, 1);
        checkParseDecimalFloatFail(string(abi.encodePacked("1e", dashes, digits)), MalformedExponentDigits.selector, 3);
    }

    /// Negative e with no digits is an error.
    function testParseLiteralDecimalFloatNegativeE() external pure {
        checkParseDecimalFloatFail("0.0e-", MalformedExponentDigits.selector, 5);
    }

    /// Negative frac is an error.
    function testParseLiteralDecimalFloatNegativeFrac() external pure {
        checkParseDecimalFloatFail("0.-1", MalformedDecimalPoint.selector, 2);
    }

    /// A fraction's exponent plus an e-notation exponent below int256.min is a
    /// value smaller than every Float, so `ParseDecimalPrecisionLoss`, from
    /// both entry points. One step above, the sum fits and the inline parse
    /// returns it, and the value is still smaller than every Float.
    function testParseExponentSumBelowInt256() external view {
        string[4] memory wraps = [
            // -1 (from ".1") + int256.min. "0.1e-" + 77 digits = 82.
            "0.1e-57896044618658097711785492504343953926634992332820282019728792003956564819968",
            "-0.1e-57896044618658097711785492504343953926634992332820282019728792003956564819968",
            "9.1e-57896044618658097711785492504343953926634992332820282019728792003956564819968",
            // -2 + (int256.min + 1) is one below int256.min.
            "9.12e-57896044618658097711785492504343953926634992332820282019728792003956564819967"
        ];
        for (uint256 i = 0; i < wraps.length; i++) {
            checkParseDecimalFloatFail(wraps[i], ParseDecimalPrecisionLoss.selector, bytes(wraps[i]).length);
            (bytes4 err, Float float) = this.parseDecimalFloatExternal(wraps[i]);
            assertEq(err, ParseDecimalPrecisionLoss.selector, "wrapper");
            assertEq(Float.unwrap(float), bytes32(0), "zero");
        }

        // -1 + (int256.min + 1) is int256.min exactly.
        string memory fits = "9.1e-57896044618658097711785492504343953926634992332820282019728792003956564819967";
        checkParseDecimalFloat(fits, 91, type(int256).min, bytes(fits).length);
        (bytes4 fitsErr,) = this.parseDecimalFloatExternal(fits);
        assertEq(fitsErr, ParseDecimalPrecisionLoss.selector, "fits wrapper");

        // No fraction: int256.min itself is the exponent.
        checkParseDecimalFloat(
            "1e-57896044618658097711785492504343953926634992332820282019728792003956564819968", 1, type(int256).min, 80
        );
        // Zero has no exponent to wrap.
        checkParseDecimalFloat(
            "0.0e-57896044618658097711785492504343953926634992332820282019728792003956564819968", 0, 0, 82
        );
        // exponent = -1 (from ".1") + int256.max (from e-notation) does NOT
        // wrap, but the value is past every Float: ExponentOverflow (#510).
        // "0.1e" = 4 chars + 77 digits = 81
        checkParseDecimalFloatFail(
            "0.1e57896044618658097711785492504343953926634992332820282019728792003956564819967",
            ExponentOverflow.selector,
            81
        );
    }

    /// An integer past int256 moves its trailing zeros into the exponent, so
    /// adding a positive e-notation exponent can wrap past int256.max: a value
    /// larger than every Float, so `ExponentOverflow` from both entry points.
    /// One below, the sum fits int256 but is still past every Float.
    function testParseExponentSumAboveInt256() external view {
        // 1e77 written out moves 77 zeros into the exponent; 77 + int256.max
        // wraps. "1" + 77 zeros + "e" + 77 digits = 156.
        string memory wraps =
            "100000000000000000000000000000000000000000000000000000000000000000000000000000e57896044618658097711785492504343953926634992332820282019728792003956564819967";
        checkParseDecimalFloatFail(wraps, ExponentOverflow.selector, bytes(wraps).length);
        (bytes4 err, Float float) = this.parseDecimalFloatExternal(wraps);
        assertEq(err, ExponentOverflow.selector, "wrapper");
        assertEq(Float.unwrap(float), bytes32(0), "zero");

        // 77 + (int256.max - 77) is int256.max exactly.
        string memory fits =
            "100000000000000000000000000000000000000000000000000000000000000000000000000000e57896044618658097711785492504343953926634992332820282019728792003956564819890";
        checkParseDecimalFloatFail(fits, ExponentOverflow.selector, bytes(fits).length);
    }

    /// ParseDecimalPrecisionLoss from the wrapper when packLossy returns
    /// lossless=false. The inline parse succeeds but the coefficient exceeds
    /// int224, so packLossy normalizes it lossily. (A10-8)
    function testParseDecimalFloatPrecisionLossFromPackLossy() external view {
        // 68 nines exceeds int224.max (~1.35e67) so packLossy must divide
        // by 10 to fit, returning lossless=false.
        (bytes4 err,) =
            this.parseDecimalFloatExternal("99999999999999999999999999999999999999999999999999999999999999999999");
        assertEq(err, ParseDecimalPrecisionLoss.selector);
    }

    /// Exponent exceeds int32 range: positive exponents the coefficient cannot
    /// lift return ExponentOverflow, negative ones a soft error. (A10-8)
    function testParseDecimalFloatExponentOverflowFromPackLossy() external view {
        // Issue #285: 1e2147483648 is 10e2147483647, which is representable.
        (bytes4 liftedErr, Float lifted) = this.parseDecimalFloatExternal("1e2147483648");
        assertEq(liftedErr, bytes4(0));
        (int256 liftedCoefficient, int256 liftedExponent) = lifted.unpack();
        assertEq(liftedCoefficient, 10);
        assertEq(liftedExponent, int256(type(int32).max));

        // Past int224 headroom, positive exponent overflow returns by value
        // (#510).
        assertEq(parseOutcome("1e2147483715"), abi.encode("return", ExponentOverflow.selector, Float.wrap(0)));
        checkParseDecimalFloatFail("1e2147483715", ExponentOverflow.selector, 12);

        // Negative exponent overflow is a very small number that rounds to
        // zero in packLossy, so the wrapper returns ParseDecimalPrecisionLoss
        // rather than reverting.
        (bytes4 err,) = this.parseDecimalFloatExternal("1e-2147483649");
        assertEq(err, ParseDecimalPrecisionLoss.selector);
    }

    /// Issue #504: past-range literals reach the caller through one channel,
    /// the returned selector, whatever their spelling.
    function testParsePastRangeOneChannel() external view {
        assertTrue(LibExactFloat.overflows(LibExactFloat.u512(2), 2147483714));
        bytes memory over = abi.encode("return", ExponentOverflow.selector, Float.wrap(0));
        assertEq(parseOutcome("2e2147483714"), over, "2e2147483714");
        assertEq(parseOutcome("-2e2147483714"), over, "-2e2147483714");
        assertEq(
            parseOutcome(string.concat("2", LibTestDecimalLiteral.zeroString(76), "1e2147483637")), over, "78 digits"
        );
        assertEq(parseOutcome(string.concat("1e1", LibTestDecimalLiteral.zeroString(80))), over, "exponent past int256");
    }

    /// A literal below the exponent floor whose coefficient carries the
    /// trailing zeros to reach it is a representable value, and parses as
    /// one: `10e-2147483649` is `1e-2147483648`. Only a literal that genuinely
    /// rounds to zero (above) is a precision loss.
    function testParseDecimalFloatBelowFloorWithTrailingZerosParses() external view {
        (bytes4 err, Float float) = this.parseDecimalFloatExternal("10e-2147483649");
        assertEq(err, bytes4(0));
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        assertEq(signedCoefficient, 1);
        assertEq(exponent, int256(type(int32).min));
    }

    /// ParseDecimalFloatExcessCharacters from the wrapper when trailing
    /// non-numeric characters remain after a valid parse. (A10-7)
    function testParseDecimalFloatExcessCharacters() external view {
        (bytes4 err,) = this.parseDecimalFloatExternal("1hello");
        assertEq(err, ParseDecimalFloatExcessCharacters.selector);

        (bytes4 err2,) = this.parseDecimalFloatExternal("1.2.3");
        assertEq(err2, ParseDecimalFloatExcessCharacters.selector);

        (bytes4 err3,) = this.parseDecimalFloatExternal("1e2e3");
        assertEq(err3, ParseDecimalFloatExcessCharacters.selector);
    }

    function testParseZeroFractionSmall() external pure {
        checkParseDecimalFloat("1", 1, 0, 1);
        checkParseDecimalFloat("1.0", 1, 0, 3);
        checkParseDecimalFloat("1.000", 1, 0, 5);
        checkParseDecimalFloat("-12.0e-3", -12, -3, 8);
        checkParseDecimalFloat("-0.0", 0, 0, 4);
        checkParseDecimalFloat("0.000e5", 0, 0, 7);
    }

    /// Issue #327: an all-zero fraction is not rescaled into the integer part.
    /// `2` + 67 zeros is past int224, so the wrapper sheds one trailing zero.
    function testParseZeroFractionPastInt224() external view {
        string memory int67 = string.concat("2", LibTestDecimalLiteral.zeroString(67));
        int256 twoE67 = 2e67;
        string[3] memory fracs = ["", ".0", ".000"];
        for (uint256 i = 0; i < fracs.length; i++) {
            string memory s = string.concat(int67, fracs[i]);
            checkParseDecimalFloat(s, twoE67, 0, bytes(s).length);
            (bytes4 err, Float float) = this.parseDecimalFloatExternal(s);
            assertEq(err, bytes4(0));
            (int256 signedCoefficient, int256 exponent) = float.unpack();
            assertEq(signedCoefficient, 2e66);
            assertEq(exponent, 1);
        }
    }

    /// Issue #327: as above, negative and with an exponent after the fraction.
    function testParseZeroFractionPastInt224NegativeExponent() external view {
        string memory int67 = string.concat("-2", LibTestDecimalLiteral.zeroString(67));
        int256 negTwoE67 = -2e67;
        string[3] memory fracs = ["", ".0", ".000"];
        for (uint256 i = 0; i < fracs.length; i++) {
            string memory s = string.concat(int67, fracs[i], "e-5");
            checkParseDecimalFloat(s, negTwoE67, -5, bytes(s).length);
            (bytes4 err, Float float) = this.parseDecimalFloatExternal(s);
            assertEq(err, bytes4(0));
            (int256 signedCoefficient, int256 exponent) = float.unpack();
            assertEq(signedCoefficient, -2e66);
            assertEq(exponent, -4);
        }
    }

    /// Issue #327: 68 nines with a zero fraction and a huge exponent overflows
    /// the exponent exactly as it does without the fraction, returning
    /// ExponentOverflow by value (#510).
    function testParseZeroFractionNinesExponentOverflow() external view {
        string memory nines = "99999999999999999999999999999999999999999999999999999999999999999999";
        bytes memory overflow = abi.encode("return", ExponentOverflow.selector, Float.wrap(0));
        string[3] memory fracs = ["", ".0", ".000"];
        for (uint256 i = 0; i < fracs.length; i++) {
            string memory s = string.concat(nines, fracs[i], "e2200000000");
            checkParseDecimalFloatFail(s, ExponentOverflow.selector, bytes(s).length);
            assertEq(parseOutcome(s), overflow, "parse outcome");
            checkAgainstRule(s);
        }
    }

    /// Issue #327: `s` and `s` + `.` + any number of zeros parse identically,
    /// inline and through the wrapper, for any integer part and exponent.
    function testParseZeroFractionEquivalentFuzz(
        uint256 value,
        uint8 digits,
        bool isNeg,
        uint8 leadingZeros,
        uint8 fracZeros,
        bool hasExponent,
        int256 e
    ) external view {
        // Up to 80 digits, so int224, int256 and past-int256 integer parts all
        // come up.
        digits = uint8(bound(digits, 1, 80));
        if (digits < 78) {
            value = bound(value, 0, 10 ** digits - 1);
        }
        fracZeros = uint8(bound(fracZeros, 1, 100));
        string memory intPart =
            string.concat(isNeg ? "-" : "", LibTestDecimalLiteral.zeroString(leadingZeros), value.toString());
        string memory exponentPart = hasExponent ? string.concat("e", Strings.toStringSigned(e)) : "";
        string memory bare = string.concat(intPart, exponentPart);
        string memory frac = string.concat(intPart, ".", LibTestDecimalLiteral.zeroString(fracZeros), exponentPart);

        (bytes4 bareErr, uint256 bareCursor, int256 bareCoefficient, int256 bareExponent) =
            this.parseDecimalFloatInlineExternal(bare);
        (bytes4 fracErr, uint256 fracCursor, int256 fracCoefficient, int256 fracExponent) =
            this.parseDecimalFloatInlineExternal(frac);
        assertEq(fracErr, bareErr, "inline error");
        assertEq(fracCoefficient, bareCoefficient, "inline coefficient");
        assertEq(fracExponent, bareExponent, "inline exponent");
        if (bareErr == bytes4(0)) {
            assertEq(bareCursor, bytes(bare).length, "bare cursor");
            assertEq(fracCursor, bytes(frac).length, "frac cursor");
        }

        assertEq(parseOutcome(frac), parseOutcome(bare), "outcome");
        checkAgainstRule(bare);
        checkAgainstRule(frac);
    }

    /// Can't have more than max total precision. Add decimals after the max int.
    function testParseLiteralDecimalFloatPrecisionRevert0() external pure {
        checkParseDecimalFloatFail(
            "57896044618658097711785492504343953926634992332820282019728792003956564819967.1",
            ParseDecimalPrecisionLoss.selector,
            79
        );
    }

    /// 69 significant digits are no Float, but fit int256, so the inline parse
    /// returns them exactly and the wrapper reports the precision loss.
    function testParseLiteralDecimalFloatPrecisionRevert1() external view {
        string memory s = "2.5789604461865809771178549250434395392663499233282028201972879200395";
        checkParseDecimalFloat(s, 25789604461865809771178549250434395392663499233282028201972879200395, -67, 69);
        (bytes4 err, Float float) = this.parseDecimalFloatExternal(s);
        assertEq(err, ParseDecimalPrecisionLoss.selector);
        assertEq(Float.unwrap(float), bytes32(0));
    }

    /// Characters a literal is made of, weighted to zeros, and one it is not.
    bytes internal constant ALPHABET = "0123456789000000.-+eEx";

    /// Strings over the literal alphabet, against the rule.
    function testParseRuleAlphabetFuzz(bytes memory seed) external view {
        bytes memory str = new bytes(seed.length);
        for (uint256 i = 0; i < seed.length; i++) {
            str[i] = ALPHABET[uint8(seed[i]) % ALPHABET.length];
        }
        checkAgainstRule(string(str));
    }

    /// `len` digits from `seed`, each zero at odds `zeroOdds` in 8, otherwise
    /// uniform.
    function digitRun(uint256 seed, uint256 len, uint256 zeroOdds) internal pure returns (bytes memory out) {
        out = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            uint256 r = uint256(keccak256(abi.encode(seed, i)));
            // A digit, below 58.
            // forge-lint: disable-next-line(unsafe-typecast)
            out[i] = r % 8 < zeroOdds ? bytes1("0") : bytes1(uint8(48 + (r >> 8) % 10));
        }
    }

    /// An exponent part: none, small, near int32.min or int32.max, near
    /// int256.min or int256.max, or digits past int256.
    function exponentOfKind(uint256 kind, int256 raw, uint256 style) internal pure returns (string memory) {
        kind = kind % 7;
        if (kind == 0) {
            return "";
        }
        string memory digits;
        if (kind == 1) {
            digits = Strings.toStringSigned(bound(raw, -200, 200));
        } else if (kind == 2) {
            digits = Strings.toStringSigned(type(int32).min + bound(raw, -300, 300));
        } else if (kind == 3) {
            digits = Strings.toStringSigned(type(int32).max + bound(raw, -300, 300));
        } else if (kind == 4) {
            digits = Strings.toStringSigned(type(int256).min + int256(bound(raw, 0, 300)));
        } else if (kind == 5) {
            digits = Strings.toStringSigned(type(int256).max - int256(bound(raw, 0, 300)));
        } else {
            // 2^255 and up, of either sign, possibly with more digits.
            uint256 past = (uint256(1) << 255) + uint256(bound(raw, 0, 300));
            digits = string.concat(raw < 0 ? "-" : "", past.toString(), raw % 3 == 0 ? "00" : "");
        }
        style = style % 3;
        bool negative = bytes(digits)[0] == "-";
        string memory marker = style == 1 ? "E" : "e";
        if (!negative && style == 2) {
            marker = "e+";
        }
        return string.concat(marker, digits);
    }

    /// What may follow a literal: nothing, or a malformed or excess tail.
    function tail(uint256 kind) internal pure returns (string memory) {
        string[9] memory tails = ["", "", "x", ".", "e", "e-", "e+", ".5", "-1"];
        return tails[kind % tails.length];
    }

    /// Literals of every shape, digit runs past int256 and exponents near and
    /// past the int32 and int256 bounds, with malformed tails, against the
    /// rule.
    function testParseRuleLiteralShapeFuzz(
        bool negative,
        uint8 leadingZeros,
        uint256 intSeed,
        uint8 intLength,
        uint8 trailingZeros,
        uint256 fracSeed,
        uint8 fracLength,
        uint8 zeroOdds,
        uint256 expKind,
        int256 expRaw,
        uint256 expStyle,
        uint256 tailKind
    ) external view {
        intLength = uint8(bound(intLength, 1, 160));
        bytes memory intDigits = digitRun(intSeed, intLength, zeroOdds % 8);
        string memory literal = string.concat(
            negative ? "-" : "",
            LibTestDecimalLiteral.zeroString(leadingZeros % 100),
            string(intDigits),
            LibTestDecimalLiteral.zeroString(trailingZeros % 100)
        );
        if (fracLength % 3 != 0) {
            literal = string.concat(literal, ".", string(digitRun(fracSeed, bound(fracLength, 1, 160), zeroOdds % 8)));
        }
        literal = string.concat(literal, exponentOfKind(expKind, expRaw, expStyle), tail(tailKind));
        checkAgainstRule(literal);
    }

    /// Around the overflow threshold `(2^223 + 2) × 10^int32.max`: a 68 digit
    /// head near 2^223 followed by `extra` digits, its leading digit near
    /// 10^(int32.max + 67), with the point anywhere in the digits.
    function testParseRuleOverflowThresholdFuzz(
        uint256 head,
        uint8 extra,
        uint256 extraSeed,
        uint8 zeroOdds,
        int8 shift,
        uint8 point,
        bool negative
    ) external view {
        head = bound(head, 2 ** 223 - 5, 2 ** 223 + 5);
        bytes memory digits = bytes.concat(bytes(head.toString()), digitRun(extraSeed, extra, zeroOdds % 9));
        uint256 fracLength = bound(point, 0, digits.length - 1);
        string memory mantissa = fracLength == 0
            ? string(digits)
            : string.concat(
                string(LibTestDecimalLiteral.slice(digits, 0, digits.length - fracLength)),
                ".",
                string(LibTestDecimalLiteral.slice(digits, digits.length - fracLength, digits.length))
            );
        // The leading digit is at 10^(int32.max + 67 + shift).
        // Lengths are far below int256.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 e = int256(type(int32).max) + 67 + bound(shift, -2, 2) - int256(digits.length - fracLength - 1);
        checkAgainstRule(string.concat(negative ? "-" : "", mantissa, "e", Strings.toStringSigned(e)));
    }

    /// Literals past int256 that the old internal steps rejected, by value.
    function testParseRulePastInt256Examples() external view {
        string memory max = Strings.toStringSigned(type(int256).max);
        string memory past = (uint256(1) << 255).toString();
        string[12] memory literals = [
            past,
            string.concat("1e", past),
            string.concat("-1e", past),
            string.concat("1e-", past),
            string.concat("0.", digitRunString(78)),
            string.concat("1e-", (uint256(1) << 255).toString(), "1"),
            string.concat("2", LibTestDecimalLiteral.zeroString(66), ".5"),
            string.concat(max, ".5"),
            string.concat(max, "e2147483647"),
            string.concat(max, "e-2147483700"),
            string.concat(past, "000e-80"),
            string.concat("1", LibTestDecimalLiteral.zeroString(200), ".", LibTestDecimalLiteral.zeroString(200), "1")
        ];
        for (uint256 i = 0; i < literals.length; i++) {
            checkAgainstRule(literals[i]);
        }
    }

    /// An integer part and a fraction that each fit int256 but whose combined
    /// digits do not: the fraction pushes the sum past int256 of its sign, or
    /// the integer rescaled by 10^77 passes uint256's int256 range.
    function testParseRuleFractionRescaleEdges() external view {
        string memory maxTenth = Strings.toStringSigned(type(int256).max / 10);
        string memory maxHundredth = Strings.toStringSigned(type(int256).max / 100);
        string memory minTenth = Strings.toStringSigned(type(int256).min / 10);
        string[9] memory literals = [
            string.concat(maxTenth, ".9"),
            string.concat(maxTenth, ".7"),
            string.concat(maxHundredth, ".99"),
            string.concat(minTenth, ".9"),
            string.concat(minTenth, ".8"),
            string.concat("1.", LibTestDecimalLiteral.zeroString(75), "1"),
            string.concat("1.", LibTestDecimalLiteral.zeroString(76), "1"),
            string.concat("-1.", LibTestDecimalLiteral.zeroString(76), "1"),
            string.concat("5.", LibTestDecimalLiteral.zeroString(76), "3")
        ];
        for (uint256 i = 0; i < literals.length; i++) {
            checkAgainstRule(literals[i]);
        }
    }

    /// A nonzero integer part with a fraction ending 10^-76 rescales by 10^76
    /// to `10^76 + 1`, inside int256. Ending 10^-77 it is `10^77 + 1`, past
    /// int256 and 78 significant digits, so no Float, and its magnitude near 1
    /// is not past every Float.
    function testParseFractionRescaleBound() external view {
        string memory atBound = string.concat("1.", LibTestDecimalLiteral.zeroString(75), "1");
        string memory pastBound = string.concat("1.", LibTestDecimalLiteral.zeroString(76), "1");
        checkParseDecimalFloat(atBound, 1e76 + 1, -76, 78);
        checkParseDecimalFloat(string.concat("-", atBound), -(1e76 + 1), -76, 79);
        checkParseDecimalFloatFail(pastBound, ParseDecimalPrecisionLoss.selector, 79);
        checkParseDecimalFloatFail(string.concat("-", pastBound), ParseDecimalPrecisionLoss.selector, 80);
        checkAgainstRule(atBound);
        checkAgainstRule(pastBound);
        checkAgainstRule(string.concat("-", pastBound));
    }

    /// Signs, zeros and the int256 bounds of the integer and fraction digits,
    /// against the rule.
    function testParseRuleMantissaEdges() external view {
        string memory max = Strings.toStringSigned(type(int256).max);
        string memory past = (uint256(1) << 255).toString();
        // 2^255 with the point after its first digit.
        string memory pastPointed = string.concat("5.", string(LibTestDecimalLiteral.slice(bytes(past), 1, 77)));
        string[24] memory literals = [
            "-0",
            "-0.0",
            "-00.000e5",
            "-0.5",
            "-00.10",
            "-1.05",
            string.concat("-", past),
            string.concat("-", past, ".0"),
            string.concat("-", past, ".5"),
            string.concat("-", past, "e-1"),
            string.concat("-", past, "e1"),
            string.concat(max, ".0"),
            string.concat("-", max, ".5"),
            string.concat("0.", max),
            string.concat("-0.", max),
            string.concat("0.", past),
            string.concat("-0.", past),
            string.concat("0.", max, "000"),
            pastPointed,
            string.concat("-", pastPointed),
            string.concat("9.", LibTestDecimalLiteral.zeroString(75), "9"),
            string.concat("-9.", LibTestDecimalLiteral.zeroString(75), "9"),
            string.concat("1.", LibTestDecimalLiteral.zeroString(76), "0"),
            string.concat("1.", LibTestDecimalLiteral.zeroString(300), "1")
        ];
        for (uint256 i = 0; i < literals.length; i++) {
            checkAgainstRule(literals[i]);
        }
    }

    function digitRunString(uint256 n) internal pure returns (string memory s) {
        s = new string(n);
        for (uint256 i = 0; i < n; i++) {
            // A digit, below 58.
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes(s)[i] = bytes1(uint8(49 + i % 9));
        }
    }

    /// Leading zeros in the exponent digits do not change its value, however
    /// many: an exponent padded past 78 digits is still the exponent it
    /// spells, and int256.min padded so is still int256.min.
    function testParseExponentLeadingZeros() external view {
        string memory pad = LibTestDecimalLiteral.zeroString(100);
        // "1e" + 100 zeros + "5" = 103.
        checkParseDecimalFloat(string.concat("1e", pad, "5"), 1, 5, 103);
        checkParseDecimalFloat(string.concat("1e-", pad, "5"), 1, -5, 104);
        checkParseDecimalFloat(string.concat("-1.5E+", pad, "5"), -15, 4, 107);
        checkParseDecimalFloat(string.concat("2.5e-", pad, "3"), 25, -4, 106);
        string memory minDigits = "57896044618658097711785492504343953926634992332820282019728792003956564819968";
        checkParseDecimalFloat(string.concat("1e-", pad, minDigits), 1, type(int256).min, 180);
        // Padded int256.min plus the fraction's -1 is below int256.min.
        string memory wraps = string.concat("0.1e-", pad, minDigits);
        checkParseDecimalFloatFail(wraps, ParseDecimalPrecisionLoss.selector, bytes(wraps).length);
        string[6] memory literals = [
            string.concat("1e", pad, "5"),
            string.concat("1e-", pad, "5"),
            string.concat("-1.5E+", pad, "5"),
            string.concat("1e-", pad, minDigits),
            wraps,
            string.concat("1e", pad, "2147483647")
        ];
        for (uint256 i = 0; i < literals.length; i++) {
            checkAgainstRule(literals[i]);
        }
    }
}
