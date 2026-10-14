// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibDecimalFloat, Float} from "../LibDecimalFloat.sol";
import {UnformatableExponent} from "../../error/ErrFormat.sol";

/// @dev Library for formatting DecimalFloat values as strings.
library LibFormatDecimalFloat {
    /// Maximum `|exponent|` supported by non-scientific formatting, applied to
    /// the value's canonical form: the coefficient without its trailing
    /// decimal zeros, the exponent raised by as many. Canonical exponents
    /// outside `[-MAX_NON_SCIENTIFIC_EXPONENT, MAX_NON_SCIENTIFIC_EXPONENT]`
    /// revert with `UnformatableExponent`, so equal Floats format alike. The
    /// cap bounds the output string to at most 69 bytes more than it: a sign,
    /// 68 digits and the zeros. Callers that need to render such values
    /// should use scientific mode.
    int256 internal constant MAX_NON_SCIENTIFIC_EXPONENT = 1000;

    /// Inline assembly takes only literal constants.
    uint256 private constant E8 = 1e8;
    uint256 private constant E16 = 1e16;
    uint256 private constant E32 = 1e32;
    uint256 private constant E64 = 1e64;
    /// ASCII `0`, `-`, `.` and `e`.
    uint256 private constant CHAR_ZERO = 0x30;
    uint256 private constant CHAR_MINUS = 0x2d;
    uint256 private constant CHAR_DOT = 0x2e;
    uint256 private constant CHAR_E = 0x65;
    /// 32 ASCII `0` bytes.
    bytes32 private constant ZEROS = 0x3030303030303030303030303030303030303030303030303030303030303030;

    /// Format a decimal float as a string. Zero is "0" at any exponent. Every
    /// other value formats from its canonical form, the coefficient without its
    /// trailing decimal zeros, so equal Floats give equal strings.
    /// Scientific: `d.ddd` then `eN` for the exponent of the leading digit, `eN`
    /// omitted when N is zero. Plain: the decimal digits with a point where
    /// needed; a canonical exponent outside
    /// `[-MAX_NON_SCIENTIFIC_EXPONENT, MAX_NON_SCIENTIFIC_EXPONENT]` reverts
    /// `UnformatableExponent` with that exponent. Scientific mode never reverts.
    /// @param float The decimal float to format.
    /// @param scientific Whether to format in scientific notation (e.g. 1e10).
    /// @return The string representation of the decimal float.
    function toDecimalString(Float float, bool scientific) internal pure returns (string memory) {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.unpack(float);
        if (signedCoefficient == 0) {
            return "0";
        }
        if (scientific) {
            return _toScientific(signedCoefficient, exponent);
        }
        return _toNonScientific(signedCoefficient, exponent);
    }

    /// Scientific notation: render as `d.dddeN` where `d` is the most
    /// significant digit, so `N` is the exponent plus the coefficient's digit
    /// count less one. When `N` is zero the `eN` part is omitted, so `1.5e0`
    /// formats as `1.5`.
    /// @param signedCoefficient The nonzero coefficient, as unpacked.
    /// @param exponent The exponent, as unpacked.
    /// @return out The formatted string.
    //slither-disable-next-line cyclomatic-complexity
    function _toScientific(int256 signedCoefficient, int256 exponent) private pure returns (string memory out) {
        bool isNeg = signedCoefficient < 0;
        uint256 absCoef;
        unchecked {
            // signedCoefficient came from `unpack` so |signedCoefficient| fits
            // int224; negation always fits uint256.
            // forge-lint: disable-next-line(unsafe-typecast)
            absCoef = isNeg ? uint256(-signedCoefficient) : uint256(signedCoefficient);
        }

        // Strip trailing decimal zeros of the coefficient, raising the
        // exponent by the same count.
        (uint256 significand, uint256 trailingZeros) = stripTrailingZeros(absCoef);
        // trailingZeros < 68.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 displayExponent = exponent + int256(trailingZeros);

        assembly ("memory-safe") {
            // Significand digits end at `out`, the exponent's digits end
            // where the significand's start: at most 68 + 10 bytes below
            // `out`, within the 0x80 of headroom above the free pointer.
            out := add(mload(0x40), 0x80)
            let start := out
            for {} 1 {} {
                start := sub(start, 1)
                mstore8(start, add(CHAR_ZERO, mod(significand, 10)))
                significand := div(significand, 10)
                if iszero(significand) { break }
            }
            let digits := sub(out, start)
            // The leading digit's exponent: `digits - 1` places above the
            // significand's own.
            displayExponent := add(displayExponent, sub(digits, 1))

            let cursor := add(out, 0x20)
            if isNeg {
                mstore8(cursor, CHAR_MINUS)
                cursor := add(cursor, 1)
            }
            mstore(cursor, mload(start))
            cursor := add(cursor, 1)
            if gt(digits, 1) {
                mstore8(cursor, CHAR_DOT)
                cursor := add(cursor, 1)
                let n := sub(digits, 1)
                for { let i := 0 } lt(i, n) { i := add(i, 0x20) } {
                    mstore(add(cursor, i), mload(add(add(start, 1), i)))
                }
                cursor := add(cursor, n)
            }
            if displayExponent {
                mstore8(cursor, CHAR_E)
                cursor := add(cursor, 1)
                let e := displayExponent
                if slt(e, 0) {
                    mstore8(cursor, CHAR_MINUS)
                    cursor := add(cursor, 1)
                    e := sub(0, e)
                }
                let eStart := start
                for {} 1 {} {
                    eStart := sub(eStart, 1)
                    mstore8(eStart, add(CHAR_ZERO, mod(e, 10)))
                    e := div(e, 10)
                    if iszero(e) { break }
                }
                let n := sub(start, eStart)
                mstore(cursor, mload(eStart))
                cursor := add(cursor, n)
            }
            mstore(out, sub(cursor, add(out, 0x20)))
            // The zero word may reach past the free pointer, which only needs
            // to cover the string's last word.
            mstore(cursor, 0)
            mstore(0x40, and(add(cursor, 0x1f), not(0x1f)))
        }
    }

    /// Non-scientific notation: render by placing a decimal point inside the
    /// coefficient's digit string according to the exponent. Does not compute
    /// `10^exponent` as an integer, so the output is valid for any canonical
    /// `|exponent| <= MAX_NON_SCIENTIFIC_EXPONENT`.
    /// @param signedCoefficient The nonzero coefficient, as unpacked.
    /// @param exponent The exponent, as unpacked.
    /// @return out The formatted string.
    //slither-disable-next-line cyclomatic-complexity
    function _toNonScientific(int256 signedCoefficient, int256 exponent) private pure returns (string memory out) {
        bool isNeg = signedCoefficient < 0;
        uint256 absCoef;
        unchecked {
            // signedCoefficient came from `unpack` so |signedCoefficient| fits
            // int224; negation always fits uint256.
            // forge-lint: disable-next-line(unsafe-typecast)
            absCoef = isNeg ? uint256(-signedCoefficient) : uint256(signedCoefficient);
        }

        // Strip trailing decimal zeros of the coefficient, raising the
        // exponent by the same count.
        (uint256 significand, uint256 trailingZeros) = stripTrailingZeros(absCoef);
        // trailingZeros < 68.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 effExp = exponent + int256(trailingZeros);
        if (effExp > MAX_NON_SCIENTIFIC_EXPONENT || effExp < -MAX_NON_SCIENTIFIC_EXPONENT) {
            revert UnformatableExponent(effExp);
        }

        assembly ("memory-safe") {
            // The digits end at `out`, at most 68 of them, within the 0x60 of
            // headroom above the free pointer.
            out := add(mload(0x40), 0x60)
            let start := out
            for {} 1 {} {
                start := sub(start, 1)
                mstore8(start, add(CHAR_ZERO, mod(significand, 10)))
                significand := div(significand, 10)
                if iszero(significand) { break }
            }
            let digits := sub(out, start)

            let cursor := add(out, 0x20)
            if isNeg {
                mstore8(cursor, CHAR_MINUS)
                cursor := add(cursor, 1)
            }
            switch slt(effExp, 0)
            case 0 {
                // Significant digits followed by `effExp` zeros.
                for { let i := 0 } lt(i, digits) { i := add(i, 0x20) } {
                    mstore(add(cursor, i), mload(add(start, i)))
                }
                cursor := add(cursor, digits)
                for { let i := 0 } lt(i, effExp) { i := add(i, 0x20) } { mstore(add(cursor, i), ZEROS) }
                cursor := add(cursor, effExp)
            }
            default {
                let fractionDigits := sub(0, effExp)
                switch gt(digits, fractionDigits)
                case 0 {
                    // "0." + leading zeros + significant digits.
                    // ASCII `0.`, left aligned.
                    mstore(cursor, or(shl(248, CHAR_ZERO), shl(240, CHAR_DOT)))
                    cursor := add(cursor, 2)
                    let leadingZeros := sub(fractionDigits, digits)
                    for { let i := 0 } lt(i, leadingZeros) { i := add(i, 0x20) } {
                        mstore(add(cursor, i), ZEROS)
                    }
                    cursor := add(cursor, leadingZeros)
                    for { let i := 0 } lt(i, digits) { i := add(i, 0x20) } {
                        mstore(add(cursor, i), mload(add(start, i)))
                    }
                    cursor := add(cursor, digits)
                }
                default {
                    // The decimal point sits inside the significant digits.
                    let integerDigits := sub(digits, fractionDigits)
                    for { let i := 0 } lt(i, integerDigits) { i := add(i, 0x20) } {
                        mstore(add(cursor, i), mload(add(start, i)))
                    }
                    cursor := add(cursor, integerDigits)
                    mstore8(cursor, CHAR_DOT)
                    cursor := add(cursor, 1)
                    start := add(start, integerDigits)
                    for { let i := 0 } lt(i, fractionDigits) { i := add(i, 0x20) } {
                        mstore(add(cursor, i), mload(add(start, i)))
                    }
                    cursor := add(cursor, fractionDigits)
                }
            }
            mstore(out, sub(cursor, add(out, 0x20)))
            // The zero word may reach past the free pointer, which only needs
            // to cover the string's last word.
            mstore(cursor, 0)
            mstore(0x40, and(add(cursor, 0x1f), not(0x1f)))
        }
    }

    /// Divides the decimal trailing zeros out of a nonzero value.
    /// @param value The nonzero value.
    /// @return significand The value without its trailing zeros.
    /// @return trailingZeros How many zeros were divided out.
    function stripTrailingZeros(uint256 value) private pure returns (uint256 significand, uint256 trailingZeros) {
        assembly ("memory-safe") {
            // The steps halve, so any count up to 127 comes out in at most one
            // step each; a nonzero uint256 has at most 77.
            if iszero(mod(value, 10)) {
                if iszero(mod(value, E64)) {
                    value := div(value, E64)
                    trailingZeros := 64
                }
                if iszero(mod(value, E32)) {
                    value := div(value, E32)
                    trailingZeros := add(trailingZeros, 32)
                }
                if iszero(mod(value, E16)) {
                    value := div(value, E16)
                    trailingZeros := add(trailingZeros, 16)
                }
                if iszero(mod(value, E8)) {
                    value := div(value, E8)
                    trailingZeros := add(trailingZeros, 8)
                }
                if iszero(mod(value, 10000)) {
                    value := div(value, 10000)
                    trailingZeros := add(trailingZeros, 4)
                }
                if iszero(mod(value, 100)) {
                    value := div(value, 100)
                    trailingZeros := add(trailingZeros, 2)
                }
                if iszero(mod(value, 10)) {
                    value := div(value, 10)
                    trailingZeros := add(trailingZeros, 1)
                }
            }
            significand := value
        }
    }
}
