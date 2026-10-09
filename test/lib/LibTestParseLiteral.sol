// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {ParseEmptyDecimalString} from "rain-string-0.3.9/src/error/ErrParse.sol";
import {
    MalformedExponentDigits,
    ParseDecimalPrecisionLoss,
    MalformedDecimalPoint,
    ParseDecimalFloatExcessCharacters
} from "src/error/ErrParse.sol";
import {ExponentOverflow} from "src/error/ErrDecimalFloat.sol";
import {LibTestExactDecimal, U512} from "test/lib/LibTestExactDecimal.sol";

/// A literal's exponent, exact past int256: `band` 0 is `v`, 1 is
/// `int256.max + v` and -1 is `int256.min - v`, with `v` positive there.
struct Exponent {
    int8 band;
    int256 v;
}

/// What `parseDecimalFloat` must do with a literal.
/// `Value`: return no error and a Float equal to `negative ? -m : m` ×
/// 10^`exponent.v`. `Revert`: revert `ExponentOverflow` with int256 parts equal
/// to the literal. Otherwise return `selector` and a zero Float.
enum Outcome {
    Selector,
    Value,
    Revert
}

struct Expected {
    Outcome outcome;
    bytes4 selector;
    bool negative;
    uint256 m;
    Exponent exponent;
}

/// Reads a decimal literal independently of the parser under test: its
/// grammar `-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?` and its exact value as
/// `±m × 10^E` with `m` free of trailing zeros, then the parse rule of
/// `parseDecimalFloat`'s NatSpec: a literal exactly a Float is that Float, a
/// literal larger in magnitude than every Float is `ExponentOverflow`, and any
/// other is `ParseDecimalPrecisionLoss`.
library LibTestParseLiteral {
    /// The largest Float coefficient magnitude of each sign.
    uint256 internal constant POSITIVE_BOUND = 2 ** 223 - 1;
    uint256 internal constant NEGATIVE_BOUND = 2 ** 223;

    function isDigit(bytes1 c) private pure returns (bool) {
        return c >= "0" && c <= "9";
    }

    function skipDigits(bytes memory s, uint256 i) private pure returns (uint256) {
        while (i < s.length && isDigit(s[i])) {
            i++;
        }
        return i;
    }

    function selector(bytes4 s) private pure returns (Expected memory e) {
        e.outcome = Outcome.Selector;
        e.selector = s;
    }

    function slice(bytes memory s, uint256 start, uint256 end) private pure returns (bytes memory out) {
        out = new bytes(end - start);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = s[start + i];
        }
    }

    function expected(string memory str) internal pure returns (Expected memory) {
        bytes memory s = bytes(str);
        uint256 i = 0;
        bool negative = s.length > 0 && s[0] == "-";
        if (negative) {
            i++;
        }
        uint256 intStart = i;
        i = skipDigits(s, i);
        if (i == intStart) {
            return selector(ParseEmptyDecimalString.selector);
        }
        bytes memory digits = slice(s, intStart, i);
        uint256 fracLen = 0;
        if (i < s.length && s[i] == ".") {
            i++;
            uint256 fracStart = i;
            i = skipDigits(s, i);
            if (i == fracStart) {
                return selector(MalformedDecimalPoint.selector);
            }
            fracLen = i - fracStart;
            digits = bytes.concat(digits, slice(s, fracStart, i));
        }
        bool expNegative = false;
        bytes memory expDigits;
        if (i < s.length && (s[i] == "e" || s[i] == "E")) {
            i++;
            if (i < s.length && (s[i] == "+" || s[i] == "-")) {
                expNegative = s[i] == "-";
                i++;
            }
            uint256 expStart = i;
            i = skipDigits(s, i);
            if (i == expStart) {
                return selector(MalformedExponentDigits.selector);
            }
            expDigits = slice(s, expStart, i);
        }
        if (i != s.length) {
            return selector(ParseDecimalFloatExcessCharacters.selector);
        }
        return classify(negative, digits, fracLen, expNegative, expDigits);
    }

    /// `digits` without leading and trailing zeros, and the count of trailing
    /// zeros dropped. Empty for zero.
    function significant(bytes memory digits) private pure returns (bytes memory, uint256) {
        uint256 first = 0;
        while (first < digits.length && digits[first] == "0") {
            first++;
        }
        uint256 end = digits.length;
        while (end > first && digits[end - 1] == "0") {
            end--;
        }
        return (slice(digits, first, end), digits.length - end);
    }

    function classify(bool negative, bytes memory digits, uint256 fracLen, bool expNegative, bytes memory expDigits)
        private
        pure
        returns (Expected memory e)
    {
        (bytes memory m, uint256 trailing) = significant(digits);
        if (m.length == 0) {
            e.outcome = Outcome.Value;
            return e;
        }
        e.negative = negative;
        uint256 n = m.length;
        // The value's exponent is the written one, less the fraction digits,
        // plus the trailing zeros dropped.
        // forge-lint: disable-next-line(unsafe-typecast)
        e.exponent = exponentOf(expNegative, expDigits, int256(trailing) - int256(fracLen));

        // The leading digit's position against the largest Float's, which
        // has 68 digits at 10^int32.max for either sign.
        int256 maxLead = 67 + int256(type(int32).max);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 c = cmpLead(e.exponent, maxLead - int256(n) + 1);
        uint256 bound = negative ? NEGATIVE_BOUND : POSITIVE_BOUND;
        bool larger;
        if (c != 0) {
            larger = c > 0;
        } else {
            // Same leading position: the top 68 digits decide, and any digit
            // past them is a nonzero tail.
            uint256 top = 0;
            for (uint256 p = 0; p < 68; p++) {
                top = top * 10 + (p < n ? uint8(m[p]) - uint8(bytes1("0")) : 0);
            }
            larger = top > bound || (top == bound && n > 68);
        }

        if (larger) {
            if (n <= 77) {
                e.m = digitsValue(m);
            }
            e.outcome = hasInt256Parts(e) ? Outcome.Revert : Outcome.Selector;
            e.selector = ExponentOverflow.selector;
            return e;
        }

        // Not larger, so a Float iff it is not below the smallest exponent
        // and its digits shifted down to int32.max fit the bound. Its leading
        // position is at most maxLead, so a band +1 exponent is unreachable.
        bool isFloat = false;
        if (e.exponent.band == 0 && e.exponent.v >= type(int32).min && n <= 68) {
            e.m = digitsValue(m);
            int256 shift = e.exponent.v > type(int32).max ? e.exponent.v - type(int32).max : int256(0);
            // forge-lint: disable-next-line(unsafe-typecast)
            if (int256(n) + shift <= 68) {
                // forge-lint: disable-next-line(unsafe-typecast)
                isFloat = e.m * 10 ** uint256(shift) <= bound;
            }
        }
        if (isFloat) {
            e.outcome = Outcome.Value;
        } else {
            e.outcome = Outcome.Selector;
            e.selector = ParseDecimalPrecisionLoss.selector;
        }
    }

    /// The value of at most 77 decimal digits.
    function digitsValue(bytes memory digits) private pure returns (uint256 m) {
        for (uint256 p = 0; p < digits.length; p++) {
            m = m * 10 + (uint8(digits[p]) - uint8(bytes1("0")));
        }
    }

    /// The written exponent plus `d`, exactly.
    function exponentOf(bool expNegative, bytes memory s, int256 d) private pure returns (Exponent memory) {
        uint256 p = 0;
        while (p < s.length && s[p] == "0") {
            p++;
        }
        // More than 78 significant digits is at least 10^78, past 2^256.
        if (s.length - p > 78) {
            return Exponent(expNegative ? int8(-1) : int8(1), type(int256).max);
        }
        U512 memory acc = LibTestExactDecimal.u512(0);
        for (; p < s.length; p++) {
            acc = LibTestExactDecimal.add(
                LibTestExactDecimal.mulSmall(acc, 10), LibTestExactDecimal.u512(uint8(s[p]) - uint8(bytes1("0")))
            );
        }
        if (acc.hi != 0) {
            return Exponent(expNegative ? int8(-1) : int8(1), type(int256).max);
        }
        uint256 x = acc.lo;
        uint256 half = uint256(type(int256).max) + 1;
        // |d| is bounded by memory, far below 2^254, so every sum here fits.
        if (!expNegative) {
            if (x >= half) {
                // x + d - int256.max, with x - int256.max in [1, 2^255].
                uint256 over = x - uint256(type(int256).max);
                if (over == half) {
                    return Exponent(1, type(int256).max);
                }
                // forge-lint: disable-next-line(unsafe-typecast)
                return normalize(1, int256(over) + d);
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 xs = int256(x);
            if (d > 0 && xs > type(int256).max - d) {
                return Exponent(1, d - (type(int256).max - xs));
            }
            return Exponent(0, xs + d);
        }
        if (x > half) {
            // int256.min - (-x + d) = x - 2^255 - d, with x - 2^255 in [1, 2^255).
            // forge-lint: disable-next-line(unsafe-typecast)
            return normalize(-1, int256(x - half) - d);
        }
        // -x fits int256, as x is at most 2^255.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 xs = x == half ? type(int256).min : -int256(x);
        if (d < 0 && xs < type(int256).min - d) {
            return Exponent(-1, (type(int256).min - d) - xs);
        }
        return Exponent(0, xs + d);
    }

    /// A band ±1 exponent whose offset `v` is not positive moved back in range.
    function normalize(int8 band, int256 v) private pure returns (Exponent memory) {
        if (v > 0) {
            return Exponent(band, v);
        }
        return Exponent(0, band > 0 ? type(int256).max + v : type(int256).min - v);
    }

    /// Compares the exponent with an in-range `x`.
    function cmpLead(Exponent memory exponent, int256 x) private pure returns (int256) {
        if (exponent.band != 0) {
            return exponent.band;
        }
        if (exponent.v == x) {
            return 0;
        }
        return exponent.v < x ? int256(-1) : int256(1);
    }

    /// Whether the literal is `c × 10^e` for int256 `c` and `e`: the fewest
    /// zeros appended to `m` that bring its exponent to int256.max, and that
    /// coefficient fits int256 for its sign.
    function hasInt256Parts(Expected memory e) private pure returns (bool) {
        if (e.m == 0 || e.exponent.band < 0) {
            return false;
        }
        uint256 bound = e.negative ? uint256(type(int256).max) + 1 : uint256(type(int256).max);
        if (e.m > bound) {
            return false;
        }
        if (e.exponent.band == 0) {
            return true;
        }
        if (e.exponent.v > 77) {
            return false;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        (uint256 hi, uint256 lo) = mul512(e.m, 10 ** uint256(e.exponent.v));
        return hi == 0 && lo <= bound;
    }

    function mul512(uint256 a, uint256 b) private pure returns (uint256 hi, uint256 lo) {
        U512 memory p = LibTestExactDecimal.mul(a, b);
        return (p.hi, p.lo);
    }

    /// Whether int256 parts `c × 10^e` equal the literal exactly: `c` with its
    /// trailing zeros moved into the exponent must be `±m × 10^E`.
    function equalsParts(Expected memory expectedValue, int256 c, int256 e) internal pure returns (bool) {
        if (c == 0 || (c < 0) != expectedValue.negative) {
            return false;
        }
        uint256 magnitude = LibTestExactDecimal.abs(c);
        uint256 z = 0;
        while (magnitude % 10 == 0) {
            magnitude /= 10;
            z++;
        }
        if (magnitude != expectedValue.m) {
            return false;
        }
        // e + z against the exponent, z at most 77.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 zs = int256(z);
        if (e > type(int256).max - zs) {
            return expectedValue.exponent.band == 1 && expectedValue.exponent.v == zs - (type(int256).max - e);
        }
        return expectedValue.exponent.band == 0 && expectedValue.exponent.v == e + zs;
    }
}
