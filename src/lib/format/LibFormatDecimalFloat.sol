// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibDecimalFloat, Float} from "../LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "../implementation/LibDecimalFloatImplementation.sol";
import {UnformatableExponent} from "../../error/ErrFormat.sol";

/// @dev Library for formatting DecimalFloat values as strings.
/// Not particularly efficient as it is intended for offchain use that doesn't
/// cost gas.
library LibFormatDecimalFloat {
    /// Maximum `|exponent|` supported by non-scientific formatting. Exponents
    /// outside `[-MAX_NON_SCIENTIFIC_EXPONENT, MAX_NON_SCIENTIFIC_EXPONENT]`
    /// revert with `UnformatableExponent`. The cap exists to prevent unbounded
    /// memory use when building the output string; callers that need to render
    /// such values should use scientific mode.
    int256 internal constant MAX_NON_SCIENTIFIC_EXPONENT = 1000;

    /// Inline assembly takes only literal constants.
    uint256 private constant E8 = 1e8;
    uint256 private constant E16 = 1e16;
    uint256 private constant E32 = 1e32;
    uint256 private constant E64 = 1e64;
    /// 32 ASCII `0` bytes.
    bytes32 private constant ZEROS = 0x3030303030303030303030303030303030303030303030303030303030303030;

    /// Format a decimal float as a string.
    /// Not particularly efficient as it is intended for offchain use that
    /// doesn't cost gas.
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

    /// Scientific notation: render as `d.dddeN` where the leading digit is the
    /// most significant digit of the maximized coefficient, so the display
    /// exponent is the maximized exponent plus 75 or 76.
    //slither-disable-next-line cyclomatic-complexity
    function _toScientific(int256 signedCoefficient, int256 exponent) private pure returns (string memory out) {
        int256 originalExponent = exponent;
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.maximizeFull(signedCoefficient, exponent);

        bool isNeg = signedCoefficient < 0;
        uint256 absCoef;
        unchecked {
            // A maximized packed coefficient is never `type(int256).min`.
            // forge-lint: disable-next-line(unsafe-typecast)
            absCoef = isNeg ? uint256(-signedCoefficient) : uint256(signedCoefficient);
        }
        int256 displayExponent = exponent + (absCoef >= 1e76 ? int256(76) : int256(75));
        // The parser reconstructs this float by calling packLossless with the
        // display exponent cast to int32. Guard here so the formatter reverts
        // cleanly rather than silently producing a string whose exponent cannot
        // be represented in int32. Both sides are checked: maximizeFull reduces
        // the stored exponent by the digit-count delta (up to ~10 for an
        // int224 coefficient), so displayExponent can be up to ~76 above the
        // original exponent.
        if (displayExponent > type(int32).max || displayExponent < type(int32).min) {
            revert UnformatableExponent(originalExponent);
        }
        (uint256 significand,) = stripTrailingZeros(absCoef);

        assembly ("memory-safe") {
            // Significand digits end at `out`, the exponent's digits end
            // where the significand's start.
            out := add(mload(0x40), 0x80)
            let start := out
            for {} 1 {} {
                start := sub(start, 1)
                mstore8(start, add(48, mod(significand, 10)))
                significand := div(significand, 10)
                if iszero(significand) { break }
            }
            let digits := sub(out, start)

            let cursor := add(out, 0x20)
            if isNeg {
                mstore8(cursor, 0x2d)
                cursor := add(cursor, 1)
            }
            mstore(cursor, mload(start))
            cursor := add(cursor, 1)
            if gt(digits, 1) {
                mstore8(cursor, 0x2e)
                cursor := add(cursor, 1)
                let n := sub(digits, 1)
                for { let i := 0 } lt(i, n) { i := add(i, 0x20) } {
                    mstore(add(cursor, i), mload(add(add(start, 1), i)))
                }
                cursor := add(cursor, n)
            }
            if displayExponent {
                mstore8(cursor, 0x65)
                cursor := add(cursor, 1)
                let e := displayExponent
                if slt(e, 0) {
                    mstore8(cursor, 0x2d)
                    cursor := add(cursor, 1)
                    e := sub(0, e)
                }
                let eStart := start
                for {} 1 {} {
                    eStart := sub(eStart, 1)
                    mstore8(eStart, add(48, mod(e, 10)))
                    e := div(e, 10)
                    if iszero(e) { break }
                }
                let n := sub(start, eStart)
                mstore(cursor, mload(eStart))
                cursor := add(cursor, n)
            }
            mstore(out, sub(cursor, add(out, 0x20)))
            mstore(cursor, 0)
            mstore(0x40, and(add(cursor, 0x3f), not(0x1f)))
        }
    }

    /// Non-scientific notation: render by placing a decimal point inside the
    /// coefficient's digit string according to the exponent. Does not compute
    /// `10^exponent` as an integer, so the output is valid for any
    /// `|exponent| <= MAX_NON_SCIENTIFIC_EXPONENT` — including exponents below
    /// `-76` that arise from near-cancellation add/sub.
    //slither-disable-next-line cyclomatic-complexity
    function _toNonScientific(int256 signedCoefficient, int256 exponent) private pure returns (string memory out) {
        if (exponent > MAX_NON_SCIENTIFIC_EXPONENT || exponent < -MAX_NON_SCIENTIFIC_EXPONENT) {
            revert UnformatableExponent(exponent);
        }

        bool isNeg = signedCoefficient < 0;
        uint256 absCoef;
        unchecked {
            // signedCoefficient came from `unpack` so |signedCoefficient| fits
            // int224; negation always fits uint256.
            // forge-lint: disable-next-line(unsafe-typecast)
            absCoef = isNeg ? uint256(-signedCoefficient) : uint256(signedCoefficient);
        }

        // When exponent > 0 the formatted integer is absCoef × 10^exponent,
        // which must fit in int224 for the parser to reconstruct the value
        // losslessly. For exponent ≥ 68, 10^68 > int224.max (≈1.34e67) so
        // even coefficient 1 overflows. Otherwise divide int224.max by
        // 10^exponent and check that absCoef doesn't exceed the quotient.
        if (exponent > 0) {
            if (exponent >= 68) {
                revert UnformatableExponent(exponent);
            }
            unchecked {
                // exponent is in [1, 67], so 10^exponent fits uint256.
                // forge-lint: disable-next-line(unsafe-typecast)
                if (absCoef > uint256(int256(type(int224).max)) / 10 ** uint256(exponent)) {
                    revert UnformatableExponent(exponent);
                }
            }
        }

        // Strip trailing decimal zeros of the coefficient, raising the
        // exponent by the same count.
        (uint256 significand, uint256 trailingZeros) = stripTrailingZeros(absCoef);
        // trailingZeros < 68.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 effExp = exponent + int256(trailingZeros);

        assembly ("memory-safe") {
            // The digits end at `out`, at most 68 of them.
            out := add(mload(0x40), 0x60)
            let start := out
            for {} 1 {} {
                start := sub(start, 1)
                mstore8(start, add(48, mod(significand, 10)))
                significand := div(significand, 10)
                if iszero(significand) { break }
            }
            let digits := sub(out, start)

            let cursor := add(out, 0x20)
            if isNeg {
                mstore8(cursor, 0x2d)
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
                    mstore(cursor, shl(240, 0x302e))
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
                    mstore8(cursor, 0x2e)
                    cursor := add(cursor, 1)
                    start := add(start, integerDigits)
                    for { let i := 0 } lt(i, fractionDigits) { i := add(i, 0x20) } {
                        mstore(add(cursor, i), mload(add(start, i)))
                    }
                    cursor := add(cursor, fractionDigits)
                }
            }
            mstore(out, sub(cursor, add(out, 0x20)))
            mstore(cursor, 0)
            mstore(0x40, and(add(cursor, 0x3f), not(0x1f)))
        }
    }

    /// Divides the decimal trailing zeros out of a nonzero value of at most 77
    /// digits.
    /// @return significand The value without its trailing zeros.
    /// @return trailingZeros How many zeros were divided out.
    function stripTrailingZeros(uint256 value) private pure returns (uint256 significand, uint256 trailingZeros) {
        assembly ("memory-safe") {
            // Each step takes half of what the previous one could, so at most
            // 76 zeros come out in at most one step each.
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
