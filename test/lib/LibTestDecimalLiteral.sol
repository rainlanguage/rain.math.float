// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {ParseEmptyDecimalString} from "rain-string-0.3.9/src/error/ErrParse.sol";
import {MalformedExponentDigits, MalformedDecimalPoint} from "../../src/error/ErrParse.sol";
import {LibExactFloat} from "./LibExactFloat.sol";

/// A signed integer below 2^256 in magnitude, or `huge` past it with its sign.
struct Wide {
    bool negative;
    uint256 magnitude;
    bool huge;
}

/// What a string starts with under the literal grammar
/// `-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?`, and the literal's exact value.
struct Literal {
    /// The malformed-literal error, or zero for a well formed literal.
    bytes4 malformed;
    /// The offset after the literal, or where the malformed literal stopped.
    uint256 cursor;
    bool negative;
    /// The number of significant digits, from the first nonzero digit to the
    /// last; zero for zero.
    uint256 count;
    /// The first `min(count, 77)` significant digits.
    uint256 kept;
    /// The exponent of the last significant digit.
    Wide lastExponent;
    /// The exponent of the last kept digit.
    Wide keptExponent;
}

/// Reads a decimal literal by its grammar, independent of the library's
/// parser, into its exact value, and decides it by the documented rule.
library LibTestDecimalLiteral {
    /// Whether `s` has an ASCII decimal digit at `i`; false past its end.
    function isDigit(bytes memory s, uint256 i) internal pure returns (bool) {
        return i < s.length && s[i] >= "0" && s[i] <= "9";
    }

    /// Whether `s` has the byte `c` at `i`; false past its end.
    function isAt(bytes memory s, uint256 i, bytes1 c) internal pure returns (bool) {
        return i < s.length && s[i] == c;
    }

    /// `x` as a `Wide`, `type(int256).min` included.
    function fromInt(int256 x) internal pure returns (Wide memory) {
        return Wide(x < 0, LibExactFloat.abs(x), false);
    }

    /// `x + d`.
    function addSmall(Wide memory x, int256 d) internal pure returns (Wide memory) {
        if (x.huge || d == 0) {
            return x;
        }
        uint256 magnitude = LibExactFloat.abs(d);
        if (x.negative == (d < 0) || x.magnitude == 0) {
            unchecked {
                uint256 sum = x.magnitude + magnitude;
                if (sum < magnitude) {
                    return Wide(d < 0, 0, true);
                }
                return Wide(d < 0, sum, false);
            }
        }
        if (x.magnitude >= magnitude) {
            uint256 diff = x.magnitude - magnitude;
            return Wide(diff != 0 && x.negative, diff, false);
        }
        return Wide(!x.negative, magnitude - x.magnitude, false);
    }

    /// Whether `a` and `b` are the same value. A `huge` value equals nothing,
    /// itself included, as its magnitude is not held.
    function eq(Wide memory a, Wide memory b) internal pure returns (bool) {
        return !a.huge && !b.huge && a.negative == b.negative && a.magnitude == b.magnitude;
    }

    /// `x` as an int256 if it is below 2^200 in magnitude.
    function moderate(Wide memory x) internal pure returns (bool, int256) {
        if (x.huge || x.magnitude >= 2 ** 200) {
            // forge-lint: disable-next-line(boolean-cst)
            return (false, 0);
        }
        // Below 2^200.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 v = int256(x.magnitude);
        // forge-lint: disable-next-line(boolean-cst)
        return (true, x.negative ? -v : v);
    }

    /// The digits `s[from, to)` as a signed integer.
    function readInteger(bytes memory s, uint256 from, uint256 to, bool negative) internal pure returns (Wide memory) {
        uint256 value = 0;
        for (uint256 i = from; i < to; i++) {
            uint256 digit = uint8(s[i]) - 48;
            if (value > (type(uint256).max - digit) / 10) {
                return Wide(negative, 0, true);
            }
            value = value * 10 + digit;
        }
        return Wide(negative && value != 0, value, false);
    }

    /// The literal at the start of `s`, by the grammar on `Literal`. A
    /// malformed literal sets `malformed` to its error and `cursor` to where it
    /// stopped, and carries no value: `negative` records a leading `-` and
    /// every other field is zero. A well formed one sets `cursor` past it and
    /// the rest of `Literal` to its exact value.
    function read(bytes memory s) internal pure returns (Literal memory lit) {
        uint256 i = 0;
        if (isAt(s, i, "-")) {
            lit.negative = true;
            i++;
        }
        uint256 intStart = i;
        while (isDigit(s, i)) {
            i++;
        }
        uint256 intEnd = i;
        if (intEnd == intStart) {
            lit.malformed = ParseEmptyDecimalString.selector;
            lit.cursor = i;
            return lit;
        }
        uint256 fracStart = intEnd;
        uint256 fracEnd = intEnd;
        if (isAt(s, i, ".")) {
            i++;
            fracStart = i;
            while (isDigit(s, i)) {
                i++;
            }
            fracEnd = i;
            if (fracEnd == fracStart) {
                lit.malformed = MalformedDecimalPoint.selector;
                lit.cursor = i;
                return lit;
            }
        }
        Wide memory written = Wide(false, 0, false);
        if (isAt(s, i, "e") || isAt(s, i, "E")) {
            i++;
            bool negativeExponent = false;
            if (isAt(s, i, "+")) {
                i++;
            } else if (isAt(s, i, "-")) {
                negativeExponent = true;
                i++;
            }
            uint256 digitsStart = i;
            while (isDigit(s, i)) {
                i++;
            }
            if (i == digitsStart) {
                lit.malformed = MalformedExponentDigits.selector;
                lit.cursor = i;
                return lit;
            }
            written = readInteger(s, digitsStart, i, negativeExponent);
        }
        lit.cursor = i;

        // The mantissa's digits in order, the point dropped.
        bytes memory digits = bytes.concat(bytes(slice(s, intStart, intEnd)), bytes(slice(s, fracStart, fracEnd)));
        uint256 first = 0;
        while (first < digits.length && digits[first] == "0") {
            first++;
        }
        if (first == digits.length) {
            return lit;
        }
        uint256 last = digits.length - 1;
        while (digits[last] == "0") {
            last--;
        }
        lit.count = last - first + 1;
        uint256 keptCount = lit.count < 77 ? lit.count : 77;
        for (uint256 j = first; j < first + keptCount; j++) {
            lit.kept = lit.kept * 10 + (uint8(digits[j]) - 48);
        }
        // The digit at index j of the digits is at 10^(intLength - 1 - j).
        // Indexes are far below int256.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 intLength = int256(intEnd - intStart);
        // forge-lint: disable-next-line(unsafe-typecast)
        lit.lastExponent = addSmall(written, intLength - 1 - int256(last));
        // forge-lint: disable-next-line(unsafe-typecast)
        lit.keptExponent = addSmall(written, intLength - int256(first + keptCount));
    }

    /// A copy of `s[from, to)`.
    function slice(bytes memory s, uint256 from, uint256 to) internal pure returns (bytes memory out) {
        out = new bytes(to - from);
        for (uint256 i = from; i < to; i++) {
            out[i - from] = s[i];
        }
    }

    /// `length` ASCII zeros, for building literals with long zero runs.
    function zeroString(uint256 length) internal pure returns (string memory) {
        bytes memory out = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            out[i] = "0";
        }
        return string(out);
    }

    /// Whether the literal's value is zero.
    function isZero(Literal memory lit) internal pure returns (bool) {
        return lit.count == 0;
    }

    /// Exactly some Float `c × 10^e`, int224 `c` and int32 `e`.
    function isFloat(Literal memory lit) internal pure returns (bool) {
        if (lit.count == 0) {
            return true;
        }
        if (lit.count > 68) {
            return false;
        }
        (bool ok, int256 e) = moderate(lit.lastExponent);
        if (!ok || e < type(int32).min) {
            return false;
        }
        // Lowering the exponent to int32.max multiplies the digits by
        // 10^lift, the smallest lift that can fit.
        int256 lift = e > type(int32).max ? e - type(int32).max : int256(0);
        if (lift > 76) {
            return false;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return lit.kept <= LibExactFloat.coefficientLimit(lit.negative) / 10 ** uint256(lift);
    }

    /// Past every Float: packing has no Float to round it to.
    function isPast(Literal memory lit) internal pure returns (bool) {
        if (lit.count == 0) {
            return false;
        }
        (bool ok, int256 e) = moderate(lit.keptExponent);
        if (!ok) {
            return !lit.keptExponent.negative;
        }
        // Dropped digits past the 77 kept add less than 10^e, and the
        // threshold is a multiple of 10^e wherever 77 digits reach it, so the
        // kept digits decide.
        return LibExactFloat.overflows(LibExactFloat.u512(lit.kept), e);
    }

    /// Whether `c × 10^e` is exactly the literal's value.
    function isValue(Literal memory lit, int256 c, int256 e) internal pure returns (bool) {
        if (c == 0 || lit.count == 0) {
            return c == 0 && lit.count == 0;
        }
        if ((c < 0) != lit.negative || lit.count > 77) {
            return false;
        }
        uint256 magnitude = LibExactFloat.abs(c);
        int256 zeros = 0;
        while (magnitude % 10 == 0) {
            magnitude /= 10;
            zeros++;
        }
        return magnitude == lit.kept && eq(addSmall(fromInt(e), zeros), lit.lastExponent);
    }
}
