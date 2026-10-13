// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {LibParseDecimalFloat} from "src/lib/parse/LibParseDecimalFloat.sol";
import {LibBytes, Pointer} from "rain-solmem-0.1.28/src/lib/LibBytes.sol";
import {Strings} from "@openzeppelin-contracts-5.7.0/utils/Strings.sol";
import {ExponentOverflow} from "src/error/ErrDecimalFloat.sol";
import {LibExactFloat} from "test/lib/LibExactFloat.sol";
import {
    ParseDecimalPrecisionLoss,
    MalformedDecimalPoint,
    MalformedExponentDigits,
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
        checkFail(string.concat("-", INT256_MAX_PLUS_TWO), ParseDecimalPrecisionLoss.selector, 78);
        checkLoss(INT256_MAX, type(int256).max, 0);
        checkFail(INT256_MAX_PLUS_ONE, ParseDecimalPrecisionLoss.selector, 77);
        // Trailing zeros do not help significant digits past int256.
        checkFail(string.concat(INT256_MAX_PLUS_ONE, "0"), ParseDecimalPrecisionLoss.selector, 78);
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
        // Significant digits past int256 with a fraction are no Float.
        checkFail(string.concat(INT256_MAX_PLUS_ONE, ".5"), ParseDecimalPrecisionLoss.selector, 79);
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

    /// A nonzero coefficient with an exponent past int256 is past every Float
    /// or below every nonzero Float, by the exponent's sign.
    function testParseNonZeroHugeExponent() external view {
        string memory s = string.concat("1e", INT256_MAX_PLUS_ONE);
        checkFail(s, ExponentOverflow.selector, bytes(s).length);
        s = string.concat("-0.1e-", INT256_MAX_PLUS_TWO);
        checkFail(s, ParseDecimalPrecisionLoss.selector, bytes(s).length);
        s = string.concat("1", zeros(80), "e", INT256_MAX_PLUS_ONE);
        checkFail(s, ExponentOverflow.selector, bytes(s).length);
    }

    /// Issue #375's literals take their errors by value: 2^255 written out is
    /// below every bound but no Float, `1e` 2^255 is past every Float, 78
    /// fraction digits are no Float, and `1e-` (2^255 + 1) is below every
    /// nonzero Float. `2` + 66 zeros + `.5` is exactly 2e67 + 5 tenths, past
    /// int224 so no Float.
    function testParseIssue375Literals() external view {
        checkFail(INT256_MAX_PLUS_ONE, ParseDecimalPrecisionLoss.selector, 77);
        string memory s = string.concat("1e", INT256_MAX_PLUS_ONE);
        checkFail(s, ExponentOverflow.selector, bytes(s).length);
        s = string.concat("0.", "123456789012345678901234567890123456789012345678901234567890123456789012345678");
        checkFail(s, ParseDecimalPrecisionLoss.selector, bytes(s).length);
        s = string.concat("1e-", INT256_MAX_PLUS_TWO);
        checkFail(s, ParseDecimalPrecisionLoss.selector, bytes(s).length);
        checkLoss(string.concat("2", zeros(66), ".5"), 2e67 + 5, -1);
    }

    /// Any int256 followed by any number of zeros parses to exactly its value
    /// when that is a Float: its significant digits fit int224 of its sign.
    /// Otherwise it is no Float, `ParseDecimalPrecisionLoss`.
    function testParseIntegerTrailingZerosFuzz(int256 c, uint8 z) external view {
        checkIntegerTrailingZeros(c, z);
    }

    /// Every int224 is a Float, so with any number of zeros it parses to
    /// exactly its value.
    function testParseIntegerTrailingZerosInt224Fuzz(int224 c, uint8 z) external view {
        checkIntegerTrailingZeros(c, z);
    }

    function checkIntegerTrailingZeros(int256 c, uint8 z) internal view {
        string memory s = string.concat(Strings.toStringSigned(c), zeros(z));
        (bytes4 err, Float float) = this.parse(s);
        uint256 significand = LibExactFloat.abs(c);
        while (significand != 0 && significand % 10 == 0) {
            significand /= 10;
        }
        if (significand > LibExactFloat.coefficientLimit(c < 0)) {
            assertEq(err, ParseDecimalPrecisionLoss.selector, "error");
            assertEq(Float.unwrap(float), bytes32(0), "float");
            return;
        }
        assertEq(err, bytes4(0), "error");
        if (c == 0) {
            assertEq(Float.unwrap(float), bytes32(0), "zero");
        } else {
            (int256 actualC, int256 actualE) = float.unpack();
            assertTrue(LibExactFloat.eq(actualC, actualE, c, int256(uint256(z))), "value");
        }
    }

    /// 78 significant digits, past int256: `head` then 0000000001, so
    /// `head` + 10^-10 times 10^int32.max, which packLossy overflows on iff
    /// `head` is at least 2^223 + 2 (#452). Each literal writes that value
    /// with the point placed differently: after leading zeros, inside the
    /// digits, or before a zero fraction.
    function checkThresholdPointPositions(uint256 head, bytes4 expected) internal view {
        string memory digits = string.concat(head.toString(), "0000000001");
        uint256 int32Max = uint256(int256(type(int32).max));
        string[6] memory literals = [
            // digits × 10^(-79 + int32.max + 69)
            string.concat("0.0", digits, "e", (int32Max + 69).toString()),
            // digits × 10^(-81 + int32.max + 71)
            string.concat("000.000", digits, "e", (int32Max + 71).toString()),
            // digits × 10^(-78 + int32.max + 68)
            string.concat("0.", digits, "e", (int32Max + 68).toString()),
            // digits × 10^(-10 + int32.max)
            string.concat(head.toString(), ".0000000001e", int32Max.toString()),
            // digits × 10^(int32.max - 10)
            string.concat(digits, ".0e", (int32Max - 10).toString()),
            // digits × 10^(int32.max - 10)
            string.concat(digits, ".000e", (int32Max - 10).toString())
        ];
        for (uint256 i = 0; i < literals.length; i++) {
            checkFail(literals[i], expected, bytes(literals[i]).length);
            string memory negative = string.concat("-", literals[i]);
            checkFail(negative, expected, bytes(negative).length);
        }
    }

    /// Just below the threshold is a lossy pack, past the largest Float of
    /// either sign though it is; at it packLossy overflows.
    function testParseOverflowThresholdPointPositions() external view {
        checkThresholdPointPositions(2 ** 223 + 1, ParseDecimalPrecisionLoss.selector);
        checkThresholdPointPositions(2 ** 223 + 2, ExponentOverflow.selector);
    }

    /// An exponent marker without digits after a mantissa past int256 is
    /// `MalformedExponentDigits`, the cursor after the marker and any sign.
    function testParseIntegerPastInt256MalformedExponent() external view {
        string memory e77 = string.concat("1", zeros(77));
        checkFail(string.concat(e77, "e"), MalformedExponentDigits.selector, 79);
        checkFail(string.concat(e77, "E+"), MalformedExponentDigits.selector, 80);
        checkFail(string.concat(e77, "e-"), MalformedExponentDigits.selector, 80);
        checkFail(string.concat(e77, "e+-1"), MalformedExponentDigits.selector, 80);
        checkFail(string.concat(e77, "e-+1"), MalformedExponentDigits.selector, 80);
        checkFail(string.concat(e77, ".5e"), MalformedExponentDigits.selector, 81);
    }

    /// A fraction past int256, 10^77 + 1, then `e` without digits.
    function testParsePastInt256MalformedExponentFractionOverflow() external view {
        checkFail(string.concat("0.1", zeros(76), "1e"), MalformedExponentDigits.selector, 81);
    }

    /// 77 fraction digits after a nonzero integer part, then `e` without
    /// digits.
    function testParsePastInt256MalformedExponentScale() external view {
        checkFail(string.concat("1.", zeros(76), "1e"), MalformedExponentDigits.selector, 80);
    }

    /// 9 * 10^75 rescaled by 10 is 9 * 10^76, past int256, then `e` without
    /// digits.
    function testParsePastInt256MalformedExponentRescale() external view {
        checkFail(string.concat("9", zeros(75), ".5e"), MalformedExponentDigits.selector, 79);
    }

    /// floor(int256.max / 10) * 10 + 8 is int256.max + 1, then `e` without
    /// digits.
    function testParsePastInt256MalformedExponentSum() external view {
        checkFail(
            "5789604461865809771178549250434395392663499233282028201972879200395656481996.8e",
            MalformedExponentDigits.selector,
            79
        );
    }
}
