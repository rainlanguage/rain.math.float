// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibParseChar} from "rain-string-0.3.9/src/lib/parse/LibParseChar.sol";
import {
    CMASK_NUMERIC_0_9,
    CMASK_NEGATIVE_SIGN,
    CMASK_PLUS_SIGN,
    CMASK_E_NOTATION,
    CMASK_ZERO,
    CMASK_DECIMAL_POINT
} from "rain-string-0.3.9/src/lib/parse/LibParseCMask.sol";
import {LibParseDecimal} from "rain-string-0.3.9/src/lib/parse/LibParseDecimal.sol";
import {
    MalformedExponentDigits,
    ParseDecimalPrecisionLoss,
    MalformedDecimalPoint,
    ParseDecimalFloatExcessCharacters,
    ParseDecimalNoSignificantDigits,
    ParseDecimalNonNegativeFractionExponent
} from "../../error/ErrParse.sol";
import {ParseEmptyDecimalString} from "rain-string-0.3.9/src/error/ErrParse.sol";
import {LibDecimalFloat, Float} from "../LibDecimalFloat.sol";
import {ExponentOverflow} from "../../error/ErrDecimalFloat.sol";

/// @title LibParseDecimalFloat
/// @notice Library for parsing decimal floating point numbers from strings.
/// Not particularly gas efficient as it is intended for off-chain use cases.
/// Main use case is ensuring consistent behaviour across all offchain
/// implementations by standardizing in Solidity.
library LibParseDecimalFloat {
    /// @dev The ASCII code of `.`.
    uint256 private constant ASCII_DECIMAL_POINT = 0x2e;
    /// @dev The ASCII code of `0`.
    uint256 private constant ASCII_ZERO = 0x30;

    /// @notice Parses the decimal literal at the start of [start, end): an
    /// optional `-`, digits, optionally `.` and digits, and optionally `e` or
    /// `E`, an optional `+` or `-`, and digits. The cursor stops after it.
    /// Returns the literal's exact value as `signedCoefficient × 10^exponent`,
    /// in no particular representation. A literal at least
    /// `(2^223 + 2) × 10^int32.max` in magnitude, where `packLossy` overflows,
    /// instead returns `ExponentOverflow`, with zeros and the cursor after the
    /// literal. Any other literal that is not exactly a Float may instead
    /// return `ParseDecimalPrecisionLoss` likewise, the band below that past
    /// the largest Float of a sign included. A literal without integer digits is `ParseEmptyDecimalString`,
    /// a `.` without digits `MalformedDecimalPoint` and an `e` without digits
    /// `MalformedExponentDigits`, each with the cursor where it stopped.
    /// @param start The starting index of the substring (inclusive).
    /// @param end The ending index of the substring (exclusive).
    /// @return errorSelector 0, or the error's selector, never reverted with.
    /// `ParseEmptyDecimalString`, `MalformedDecimalPoint`,
    /// `MalformedExponentDigits` and `ParseDecimalPrecisionLoss` each take a
    /// `uint256 position`, which a reverting caller takes from `cursor`.
    /// `ExponentOverflow` is `ExponentOverflow(int256, int256)` from
    /// ErrDecimalFloat.sol, so a reverting caller encodes two words, not the
    /// cursor alone.
    /// @return cursor The position in the string after parsing.
    /// @return signedCoefficient The signed coefficient of the parsed decimal
    /// float.
    /// @return exponent The exponent of the parsed decimal float.
    //slither-disable-next-line cyclomatic-complexity
    function parseDecimalFloatInline(uint256 start, uint256 end)
        internal
        pure
        returns (bytes4 errorSelector, uint256 cursor, int256 signedCoefficient, int256 exponent)
    {
        unchecked {
            cursor = start;
            cursor += LibParseChar.isMask(cursor, end, CMASK_NEGATIVE_SIGN);
            bool isNegative = cursor != start;
            {
                uint256 intStart = cursor;
                cursor = LibParseChar.skipMask(cursor, end, CMASK_NUMERIC_0_9);
                if (cursor == intStart) {
                    return (ParseEmptyDecimalString.selector, cursor, 0, 0);
                }

                (bytes4 intErrorSelector, uint256 intValue) = LibParseDecimal.unsafeDecimalStringToInt(intStart, cursor);
                // A nonempty digit run fails only past uint256. int256 holds
                // up to 2^255 - 1, and 2^255 when negative.
                if (intErrorSelector != 0 || intValue > uint256(type(int256).max) + (isNegative ? 1 : 0)) {
                    return parseDecimalFloatPastInt256(start, end);
                }
                // 2^255 casts to int256.min, which negates to itself.
                // forge-lint: disable-next-line(unsafe-typecast)
                signedCoefficient = isNegative ? -int256(intValue) : int256(intValue);
            }

            int256 fracValue = int256(LibParseChar.isMask(cursor, end, CMASK_DECIMAL_POINT));
            if (fracValue != 0) {
                cursor++;
                uint256 fracStart = cursor;
                cursor = LibParseChar.skipMask(cursor, end, CMASK_NUMERIC_0_9);
                if (cursor == fracStart) {
                    return (MalformedDecimalPoint.selector, cursor, 0, 0);
                }
                // Trailing zeros are allowed in fractional literals but should
                // not be counted in the precision.
                // The scan stops at the decimal point at the latest.
                uint256 nonZeroCursor = cursor;
                assembly ("memory-safe") {
                    // 0x30 is '0'.
                    for {} eq(byte(0, mload(sub(nonZeroCursor, 1))), 0x30) {} {
                        nonZeroCursor := sub(nonZeroCursor, 1)
                    }
                }

                // An all-zero fraction is the same literal as no fraction.
                if (nonZeroCursor != fracStart) {
                    (bytes4 fracErrorSelector, uint256 fracDigits) =
                        LibParseDecimal.unsafeDecimalStringToInt(fracStart, nonZeroCursor);
                    if (fracErrorSelector != 0 || fracDigits > uint256(type(int256).max)) {
                        return parseDecimalFloatPastInt256(start, end);
                    }
                    // Frac value inherits its sign from the coefficient.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    fracValue = isNegative ? -int256(fracDigits) : int256(fracDigits);

                    // We want to _decrease_ the exponent by the number of digits in the
                    // fractional part.
                    // _technically_ these numbers could be out of range but in
                    // the intended use case that would imply a memory region that
                    // is physically impossible to exist.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    exponent = int256(fracStart) - int256(nonZeroCursor);
                    // nonZeroCursor > fracStart here, as the scan stops at the
                    // point, so exponent is negative. Unreachable otherwise, as
                    // a zero or positive exponent would misread the value.
                    if (exponent >= 0) {
                        revert ParseDecimalNonNegativeFractionExponent(start);
                    }

                    if (signedCoefficient == 0) {
                        signedCoefficient = fracValue;
                    } else {
                        // exponent is negative here.
                        // forge-lint: disable-next-line(unsafe-typecast)
                        uint256 scale = uint256(-exponent);
                        // A nonzero coefficient times 10^77 is past int256.
                        if (scale > 76) {
                            return parseDecimalFloatPastInt256(start, end);
                        }
                        scale = 10 ** scale;
                        // scale [10, 1e76]
                        // forge-lint: disable-next-line(unsafe-typecast)
                        int256 rescaledIntValue = signedCoefficient * int256(scale);
                        int256 sum = rescaledIntValue + fracValue;
                        // fracValue is nonzero with the coefficient's sign, so
                        // the sum wraps iff it moves against that sign.
                        if (
                            // forge-lint: disable-next-line(unsafe-typecast)
                            rescaledIntValue / int256(scale) != signedCoefficient
                                || (sum < rescaledIntValue) != (fracValue < 0)
                        ) {
                            return parseDecimalFloatPastInt256(start, end);
                        }
                        signedCoefficient = sum;
                    }
                }
            }

            int256 eValue = int256(LibParseChar.isMask(cursor, end, CMASK_E_NOTATION));
            if (eValue != 0) {
                cursor++;
                uint256 eStart = cursor;
                // The int parser does not take `+`, so a `+` is stepped over
                // rather than handed to it.
                if (LibParseChar.isMask(cursor, end, CMASK_PLUS_SIGN) == 1) {
                    cursor++;
                    eStart = cursor;
                } else {
                    cursor += LibParseChar.isMask(cursor, end, CMASK_NEGATIVE_SIGN);
                }
                {
                    uint256 digitsStart = cursor;
                    cursor = LibParseChar.skipMask(cursor, end, CMASK_NUMERIC_0_9);
                    if (cursor == digitsStart) {
                        return (MalformedExponentDigits.selector, cursor, 0, 0);
                    }
                }

                {
                    (bytes4 eErrorSelector, int256 eValueTmp) =
                        LibParseDecimal.unsafeDecimalStringToSignedInt(eStart, cursor);
                    // Exponent digits fail only past int256, so a nonzero
                    // coefficient is past every Float or below every
                    // nonzero Float by the exponent's sign. The failed parse
                    // leaves eValueTmp zero.
                    if (eErrorSelector != 0) {
                        if (signedCoefficient != 0) {
                            return (
                                LibParseChar.isMask(eStart, end, CMASK_NEGATIVE_SIGN) == 1
                                    ? ParseDecimalPrecisionLoss.selector
                                    : ExponentOverflow.selector,
                                cursor,
                                0,
                                0
                            );
                        }
                    }
                    eValue = eValueTmp;
                }

                {
                    // The sum wraps exactly when it moves against eValue's
                    // sign. Only a fraction sets exponent, to a negative, so
                    // it wraps only below int256.min, where the nonzero value
                    // is below every nonzero Float.
                    int256 newExponent = exponent + eValue;
                    if ((newExponent < exponent) != (eValue < 0)) {
                        return (ParseDecimalPrecisionLoss.selector, cursor, 0, 0);
                    }
                    exponent = newExponent;
                }
                // Only an e-notation exponent reaches the overflow threshold.
                if (
                    exponent > LibDecimalFloat.NEVER_PAST_EXPONENT
                        && LibDecimalFloat.isPastEveryFloat(
                            // int256.min negates to itself, which casts to 2^255.
                            // forge-lint: disable-next-line(unsafe-typecast)
                            uint256(signedCoefficient < 0 ? -signedCoefficient : signedCoefficient),
                            exponent
                        )
                ) {
                    return (ExponentOverflow.selector, cursor, 0, 0);
                }
            }

            if (signedCoefficient == 0) {
                // Normalize zero to have exponent zero. This ensures that parsed
                // floats follow the behaviour of packed floats.
                exponent = 0;
            }
        }
    }

    /// @notice `parseDecimalFloatInline` for a literal whose digits the int256
    /// steps there cannot hold. Reads the significant digits, from the first
    /// nonzero digit to the last, and the exponent of the last exactly, and
    /// returns them when both fit int256 and the value is below the overflow
    /// threshold, `ExponentOverflow` when it is at or past it. Otherwise the
    /// literal has more than 68 significant digits or an exponent past int256,
    /// so is no Float, and the error is chosen by its value as
    /// `parseDecimalFloatInline` documents.
    /// Each caller has seen a nonzero digit in the mantissa: integer digits
    /// past int256, a fraction with a nonzero digit, or a nonzero integer
    /// part. Zero literals all return from `parseDecimalFloatInline`.
    /// @param start The start of the literal, at its sign if any, before
    /// integer digits.
    /// @param end The end of the whole string.
    /// @return errorSelector The error selector if an error occurred,
    /// otherwise 0.
    /// @return cursor The position after the literal, or of a malformed part.
    /// @return signedCoefficient The significant digits, signed.
    /// @return exponent The exponent of the last significant digit.
    function parseDecimalFloatPastInt256(uint256 start, uint256 end)
        private
        pure
        returns (bytes4 errorSelector, uint256 cursor, int256 signedCoefficient, int256 exponent)
    {
        unchecked {
            uint256 intEnd;
            uint256 fracStart;
            (errorSelector, cursor, intEnd, fracStart) = scanMantissa(start, end);
            if (errorSelector != 0) {
                return (errorSelector, cursor, 0, 0);
            }
            (uint256 magnitude, uint256 digitCount, int256 lastExponent) =
                readSignificantDigits(start, intEnd, fracStart, cursor, end);
            int256 eValue;
            (errorSelector, cursor, eValue) = scanExponent(cursor, end);
            if (errorSelector != 0) {
                return (errorSelector, cursor, 0, 0);
            }

            exponent = eValue + lastExponent;
            // The sum wraps exactly when it moves against lastExponent's sign.
            if ((exponent < eValue) != (lastExponent < 0)) {
                return (lastExponent < 0 ? ParseDecimalPrecisionLoss.selector : ExponentOverflow.selector, cursor, 0, 0);
            }

            bool isNegative = LibParseChar.isMask(start, end, CMASK_NEGATIVE_SIGN) == 1;
            if (digitCount <= 77 && magnitude <= uint256(type(int256).max) + (isNegative ? 1 : 0)) {
                if (
                    exponent > LibDecimalFloat.NEVER_PAST_EXPONENT
                        && LibDecimalFloat.isPastEveryFloat(magnitude, exponent)
                ) {
                    return (ExponentOverflow.selector, cursor, 0, 0);
                }
                // magnitude is at most 2^255, which casts to int256.min and
                // negates to itself.
                // forge-lint: disable-next-line(unsafe-typecast)
                signedCoefficient = int256(magnitude);
                return (0, cursor, isNegative ? -signedCoefficient : signedCoefficient, exponent);
            }

            // At least 77 significant digits. magnitude is the first 77, the
            // value's floor at 10^floorExponent, and a floor at or below
            // 10^int32.max is past every Float exactly when the value is, as
            // the threshold is a multiple of it. Above, 77 digits are past
            // anyway. An exponent wrapped past int256.max is past too.
            // digitCount is bounded by memory.
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 floorExponent = exponent + int256(digitCount - 77);
            if (floorExponent < exponent || LibDecimalFloat.isPastEveryFloat(magnitude, floorExponent)) {
                return (ExponentOverflow.selector, cursor, 0, 0);
            }
            return (ParseDecimalPrecisionLoss.selector, cursor, 0, 0);
        }
    }

    /// @notice The integer digits, at least one, and any fraction of the
    /// literal at `start`.
    /// @param start The start of the literal, at its sign if any.
    /// @param end The end of the whole string.
    /// @return errorSelector `MalformedDecimalPoint` for a `.` without digits,
    /// otherwise 0.
    /// @return cursor The position after the digits, or after the bare `.`.
    /// @return intEnd The end of the integer digits.
    /// @return fracStart The start of the fraction digits, or `intEnd`
    /// without a fraction.
    function scanMantissa(uint256 start, uint256 end)
        private
        pure
        returns (bytes4 errorSelector, uint256 cursor, uint256 intEnd, uint256 fracStart)
    {
        unchecked {
            cursor = start + LibParseChar.isMask(start, end, CMASK_NEGATIVE_SIGN);
            intEnd = LibParseChar.skipMask(cursor, end, CMASK_NUMERIC_0_9);
            cursor = intEnd;
            fracStart = intEnd;
            if (LibParseChar.isMask(cursor, end, CMASK_DECIMAL_POINT) == 1) {
                cursor++;
                fracStart = cursor;
                cursor = LibParseChar.skipMask(cursor, end, CMASK_NUMERIC_0_9);
                if (cursor == fracStart) {
                    errorSelector = MalformedDecimalPoint.selector;
                }
            }
        }
    }

    /// @notice The significant digits of a well formed mantissa, from its
    /// first nonzero digit to its last. A mantissa without a nonzero digit,
    /// which `parseDecimalFloatPastInt256` never passes, reverts
    /// `ParseDecimalNoSignificantDigits`, as the strip back from its end would
    /// have no nonzero digit to stop at.
    /// @param start The start of the literal, at its sign if any.
    /// @param intEnd The end of the integer digits.
    /// @param fracStart The start of the fraction digits, or `intEnd`.
    /// @param digitsEnd The end of the mantissa's digits.
    /// @param end The end of the whole string.
    /// @return magnitude The first 77 significant digits, which fit uint256.
    /// @return digitCount The number of significant digits, at least one.
    /// @return lastExponent The exponent of the last significant digit.
    function readSignificantDigits(uint256 start, uint256 intEnd, uint256 fracStart, uint256 digitsEnd, uint256 end)
        private
        pure
        returns (uint256 magnitude, uint256 digitCount, int256 lastExponent)
    {
        unchecked {
            uint256 sigStart = LibParseChar.skipMask(start, intEnd, CMASK_NEGATIVE_SIGN | CMASK_ZERO);
            if (sigStart == intEnd) {
                sigStart = LibParseChar.skipMask(fracStart, digitsEnd, CMASK_ZERO);
            }
            if (sigStart == digitsEnd) {
                revert ParseDecimalNoSignificantDigits(start);
            }
            // sigStart holds a nonzero digit, so stepping back over zeros and
            // the point stops at or after it.
            uint256 sigEnd = digitsEnd;
            while (LibParseChar.isMask(sigEnd - 1, end, CMASK_ZERO | CMASK_DECIMAL_POINT) == 1) {
                sigEnd--;
            }
            // Offsets are bounded by memory.
            // forge-lint: disable-next-line(unsafe-typecast)
            lastExponent = sigEnd <= intEnd ? int256(intEnd - sigEnd) : -int256(sigEnd - fracStart);
            for (uint256 p = sigStart; p < sigEnd; p++) {
                uint256 char;
                assembly ("memory-safe") {
                    char := byte(0, mload(p))
                }
                if (char != ASCII_DECIMAL_POINT) {
                    if (digitCount < 77) {
                        magnitude = magnitude * 10 + (char - ASCII_ZERO);
                    }
                    digitCount++;
                }
            }
        }
    }

    /// @notice The exponent of a well formed mantissa ending at `cursor`, if
    /// any.
    /// @param cursor The end of the mantissa.
    /// @param end The end of the whole string.
    /// @return errorSelector `MalformedExponentDigits` for an `e` without
    /// digits; for digits past int256, `ExponentOverflow` when positive and
    /// `ParseDecimalPrecisionLoss` when negative, as a nonzero mantissa is
    /// then past every Float or below every nonzero Float; otherwise 0.
    /// @return cursorAfter The position after the exponent, or of the
    /// malformed part.
    /// @return eValue The exponent, zero without one or on error.
    function scanExponent(uint256 cursor, uint256 end)
        private
        pure
        returns (bytes4 errorSelector, uint256 cursorAfter, int256 eValue)
    {
        unchecked {
            if (LibParseChar.isMask(cursor, end, CMASK_E_NOTATION) == 0) {
                return (0, cursor, 0);
            }
            cursor++;
            uint256 eStart = cursor;
            if (LibParseChar.isMask(cursor, end, CMASK_PLUS_SIGN) == 1) {
                cursor++;
                eStart = cursor;
            } else {
                cursor += LibParseChar.isMask(cursor, end, CMASK_NEGATIVE_SIGN);
            }
            bool eNegative = cursor != eStart;
            uint256 digitsStart = cursor;
            cursor = LibParseChar.skipMask(cursor, end, CMASK_NUMERIC_0_9);
            if (cursor == digitsStart) {
                return (MalformedExponentDigits.selector, cursor, 0);
            }
            (errorSelector, eValue) = LibParseDecimal.unsafeDecimalStringToSignedInt(eStart, cursor);
            // Digits fail only past int256.
            if (errorSelector != 0) {
                return (eNegative ? ParseDecimalPrecisionLoss.selector : ExponentOverflow.selector, cursor, 0);
            }
            return (0, cursor, eValue);
        }
    }

    /// @notice Parses a decimal float from a string. This a high-level wrapper
    /// around `parseDecimalFloatInline` that handles string memory layout and
    /// returns a packed `Float` amenable to subsequent operations with
    /// `LibDecimalFloat`. A malformed literal returns its
    /// `parseDecimalFloatInline` error, and a well formed one followed by more
    /// characters `ParseDecimalFloatExcessCharacters`. A literal at or
    /// past the overflow threshold `parseDecimalFloatInline` states is
    /// `ExponentOverflow`, returned by value and never a revert. Any
    /// other literal that is not exactly a Float returns
    /// `ParseDecimalPrecisionLoss`.
    /// @param str The string to parse.
    /// @return errorSelector 0, or the error's selector, never reverted with.
    /// `ParseEmptyDecimalString`, `MalformedDecimalPoint`,
    /// `MalformedExponentDigits` and `ParseDecimalPrecisionLoss` each take a
    /// `uint256 position`, which this function does not return.
    /// `ExponentOverflow` is `ExponentOverflow(int256, int256)` from
    /// ErrDecimalFloat.sol, and `ParseDecimalFloatExcessCharacters` takes no
    /// arguments.
    /// @return result The parsed `Float` if no error occurred, otherwise zero.
    function parseDecimalFloat(string memory str) internal pure returns (bytes4, Float) {
        uint256 start;
        uint256 end;
        assembly ("memory-safe") {
            start := add(str, 0x20)
            end := add(start, mload(str))
        }
        (bytes4 errorSelector, uint256 cursor, int256 signedCoefficient, int256 exponent) =
            parseDecimalFloatInline(start, end);
        if (cursor != end) {
            // A malformed literal keeps its error. A well formed one, value
            // errors included as they stop after the literal, has more
            // characters after it.
            if (
                errorSelector == 0 || errorSelector == ParseDecimalPrecisionLoss.selector
                    || errorSelector == ExponentOverflow.selector
            ) {
                return (ParseDecimalFloatExcessCharacters.selector, Float.wrap(0));
            }
            return (errorSelector, Float.wrap(0));
        }
        if (errorSelector != 0) {
            return (errorSelector, Float.wrap(0));
        }
        // Every literal packLossy would revert ExponentOverflow on returned
        // that selector above. packLossy is lossy for every other literal
        // that is not exactly a Float: too many digits, past the largest
        // Float of its sign, or below every nonzero Float (e.g.
        // 1e-2147483649, which packs to FLOAT_ZERO). Each is reported as
        // ParseDecimalPrecisionLoss.
        (Float result, bool lossless) = LibDecimalFloat.packLossy(signedCoefficient, exponent);
        if (!lossless) {
            return (ParseDecimalPrecisionLoss.selector, Float.wrap(0));
        }
        return (0, result);
    }
}
