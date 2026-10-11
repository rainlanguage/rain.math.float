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
    ParseDecimalFloatExcessCharacters
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
    /// @notice Parses the decimal literal at the start of [start, end): an
    /// optional `-`, digits, optionally `.` and digits, and optionally `e` or
    /// `E`, an optional `+` or `-`, and digits. The cursor stops after it.
    /// Returns the literal's exact value as `signedCoefficient × 10^exponent`,
    /// in no particular representation. A literal that is not exactly a Float
    /// may instead return, with zeros and the cursor after the literal,
    /// `ExponentOverflow` when it is past every Float, at least
    /// `(2^223 + 2) × 10^int32.max` in magnitude so packing has no Float to
    /// round it to, and `ParseDecimalPrecisionLoss` otherwise. A literal
    /// without integer digits is `ParseEmptyDecimalString`, a `.` without
    /// digits `MalformedDecimalPoint` and an `e` without digits
    /// `MalformedExponentDigits`, each with the cursor where it stopped.
    /// @param start The starting index of the substring (inclusive).
    /// @param end The ending index of the substring (exclusive).
    /// @return errorSelector The error selector if an error occurred, otherwise
    /// 0.
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
                    // Should not be possible but guard against it in case.
                    if (exponent > 0) {
                        return (MalformedExponentDigits.selector, cursor, 0, 0);
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
    /// returns them when both fit int256. Otherwise the literal has more than
    /// 68 significant digits or an exponent past int256, so is no Float, and
    /// the error is chosen by its value as `parseDecimalFloatInline` documents.
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
            (uint256 magnitude, uint256 leading, uint256 digitCount, int256 lastExponent) =
                readSignificantDigits(start, intEnd, fracStart, cursor, end);
            int256 eValue;
            (errorSelector, cursor, eValue) = scanExponent(cursor, end);
            if (errorSelector == MalformedExponentDigits.selector) {
                return (errorSelector, cursor, 0, 0);
            }
            if (digitCount == 0) {
                return (0, cursor, 0, 0);
            }
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
                // magnitude is at most 2^255, which casts to int256.min and
                // negates to itself.
                // forge-lint: disable-next-line(unsafe-typecast)
                signedCoefficient = int256(magnitude);
                return (0, cursor, isNegative ? -signedCoefficient : signedCoefficient, exponent);
            }

            // At least 77 significant digits, past every Float iff the floor
            // at 10^int32.max is at least 2^223 + 2: the leading digit is
            // above 10^(int32.max + 67), or at it with those 68 digits.
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 leadingAtCeiling = int256(type(int32).max) + 68 - int256(digitCount);
            if (exponent > leadingAtCeiling || (exponent == leadingAtCeiling && leading >= 2 ** 223 + 2)) {
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
    /// first nonzero digit to its last.
    /// @param start The start of the literal, at its sign if any.
    /// @param intEnd The end of the integer digits.
    /// @param fracStart The start of the fraction digits, or `intEnd`.
    /// @param digitsEnd The end of the mantissa's digits.
    /// @param end The end of the whole string.
    /// @return magnitude The first 77 significant digits, which fit uint256.
    /// @return leading The first 68 significant digits: the floor at
    /// 10^int32.max of a value whose leading digit is at 10^(int32.max + 67).
    /// @return digitCount The number of significant digits, zero for zero.
    /// @return lastExponent The exponent of the last significant digit.
    function readSignificantDigits(uint256 start, uint256 intEnd, uint256 fracStart, uint256 digitsEnd, uint256 end)
        private
        pure
        returns (uint256 magnitude, uint256 leading, uint256 digitCount, int256 lastExponent)
    {
        unchecked {
            uint256 sigStart = LibParseChar.skipMask(start, intEnd, CMASK_NEGATIVE_SIGN | CMASK_ZERO);
            if (sigStart == intEnd) {
                sigStart = LibParseChar.skipMask(fracStart, digitsEnd, CMASK_ZERO);
            }
            if (sigStart == digitsEnd) {
                return (0, 0, 0, 0);
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
                if (char != 0x2e) {
                    if (digitCount < 77) {
                        magnitude = magnitude * 10 + (char - 0x30);
                    }
                    digitCount++;
                    if (digitCount == 68) {
                        leading = magnitude;
                    }
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
    /// characters `ParseDecimalFloatExcessCharacters`. A literal past every
    /// Float, as `parseDecimalFloatInline` defines it, is `ExponentOverflow`:
    /// a revert from packing or the returned selector. Any other literal that
    /// is not exactly a Float returns `ParseDecimalPrecisionLoss`.
    /// @param str The string to parse.
    /// @return errorSelector The error selector if an error occurred, otherwise
    /// 0.
    /// @return result The parsed `Float` if no error occurred, otherwise zero.
    function parseDecimalFloat(string memory str) internal pure returns (bytes4, Float) {
        uint256 start;
        uint256 end;
        assembly {
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
        // packLossy handles the two exponent-overflow directions differently:
        // - Positive exponent overflow is first met by lifting the
        //   coefficient to lower the exponent to int32.max (e.g.
        //   1e2147483648 is 10e2147483647). Only when the coefficient
        //   has no headroom left does packLossy revert with
        //   ExponentOverflow, as there is no meaningful approximation.
        // - Negative exponent overflow is first met by shedding trailing
        //   digits of the coefficient to lift the exponent to int32.min
        //   (e.g. 10e-2147483649 is 1e-2147483648, which packs
        //   losslessly). Only a number that genuinely rounds to zero
        //   (e.g. 1e-2147483649) makes packLossy return
        //   (FLOAT_ZERO, false), and we report ParseDecimalPrecisionLoss.
        (Float result, bool lossless) = LibDecimalFloat.packLossy(signedCoefficient, exponent);
        if (!lossless) {
            return (ParseDecimalPrecisionLoss.selector, Float.wrap(0));
        }
        return (0, result);
    }
}
