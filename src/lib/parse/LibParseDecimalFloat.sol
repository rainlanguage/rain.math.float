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
    CMASK_DECIMAL_POINT,
    CMASK_COMMA
} from "rain-string-0.3.9/src/lib/parse/LibParseCMask.sol";
import {LibParseDecimal} from "rain-string-0.3.9/src/lib/parse/LibParseDecimal.sol";
import {
    MalformedExponentDigits,
    ParseDecimalPrecisionLoss,
    MalformedDecimalPoint,
    ParseDecimalFloatExcessCharacters
} from "../../error/ErrParse.sol";
import {ExponentOverflow} from "../../error/ErrDecimalFloat.sol";
import {ParseEmptyDecimalString, ParseDecimalOverflow} from "rain-string-0.3.9/src/error/ErrParse.sol";
import {LibDecimalFloat, Float} from "../LibDecimalFloat.sol";

/// @title LibParseDecimalFloat
/// @notice Library for parsing decimal floating point numbers from strings.
/// Not particularly gas efficient as it is intended for off-chain use cases.
/// Main use case is ensuring consistent behaviour across all offchain
/// implementations by standardizing in Solidity.
library LibParseDecimalFloat {
    /// @notice Parses a decimal float from a substring defined by [start, end).
    /// Commas are never consumed, so a comma ends the literal.
    /// @param start The starting index of the substring (inclusive).
    /// @param end The ending index of the substring (exclusive).
    /// @return The error selector if an error occurred, otherwise 0.
    /// @return The position in the string after parsing.
    /// @return The signed coefficient of the parsed decimal float.
    /// @return The exponent of the parsed decimal float.
    function parseDecimalFloatInline(uint256 start, uint256 end)
        internal
        pure
        returns (bytes4, uint256, int256, int256)
    {
        return parseDecimalFloatInline(start, end, false);
    }

    /// @notice Parses a decimal float from a substring defined by [start, end),
    /// optionally accepting commas as thousands separators in the integer
    /// part, e.g. `1,000` or `-12,345.67`.
    /// A comma is consumed only where it follows a leading group of one to
    /// three digits or a previous comma group, and is itself followed by
    /// exactly three digits. Any other comma ends the literal exactly as it
    /// does when `commas` is false, so `1,2`, `1000,000` and `1,0000` all stop
    /// before their first comma. The value parsed is the value of the same
    /// digits without commas.
    /// @param start The starting index of the substring (inclusive).
    /// @param end The ending index of the substring (exclusive).
    /// @param commas Whether to accept commas as thousands separators.
    /// @return errorSelector The error selector if an error occurred, otherwise
    /// 0.
    /// @return cursor The position in the string after parsing.
    /// @return signedCoefficient The signed coefficient of the parsed decimal
    /// float.
    /// @return exponent The exponent of the parsed decimal float.
    function parseDecimalFloatInline(uint256 start, uint256 end, bool commas)
        internal
        pure
        returns (bytes4 errorSelector, uint256 cursor, int256 signedCoefficient, int256 exponent)
    {
        unchecked {
            cursor = start;
            cursor = LibParseChar.skipMask(cursor, end, CMASK_NEGATIVE_SIGN);
            bool isNegative = cursor != start;
            {
                uint256 intStart = cursor;
                cursor = LibParseChar.skipMask(cursor, end, CMASK_NUMERIC_0_9);
                if (cursor == intStart) {
                    return (ParseEmptyDecimalString.selector, cursor, 0, 0);
                }

                (bytes4 signedCoefficientErrorSelector, int256 signedCoefficientTmp) =
                    LibParseDecimal.unsafeDecimalStringToSignedInt(start, cursor);
                if (signedCoefficientErrorSelector != 0) {
                    return (signedCoefficientErrorSelector, cursor, 0, 0);
                }
                signedCoefficient = signedCoefficientTmp;

                if (commas && cursor - intStart <= 3) {
                    bytes4 groupsErrorSelector;
                    (groupsErrorSelector, cursor, signedCoefficient) =
                        parseCommaGroups(cursor, end, isNegative, signedCoefficient);
                    if (groupsErrorSelector != 0) {
                        return (groupsErrorSelector, cursor, 0, 0);
                    }
                }
            }

            int256 fracValue = int256(LibParseChar.isMask(cursor, end, CMASK_DECIMAL_POINT));
            if (fracValue != 0) {
                fracValue = 0;
                cursor++;
                uint256 fracStart = cursor;
                cursor = LibParseChar.skipMask(cursor, end, CMASK_NUMERIC_0_9);
                if (cursor == fracStart) {
                    return (MalformedDecimalPoint.selector, cursor, 0, 0);
                }
                // Trailing zeros are allowed in fractional literals but should
                // not be counted in the precision.
                uint256 nonZeroCursor = cursor;
                while (LibParseChar.isMask(nonZeroCursor - 1, end, CMASK_ZERO) == 1) {
                    nonZeroCursor--;
                }

                if (nonZeroCursor != fracStart) {
                    (bytes4 fracErrorSelector, int256 fracValueTmp) =
                        LibParseDecimal.unsafeDecimalStringToSignedInt(fracStart, nonZeroCursor);
                    if (fracErrorSelector != 0) {
                        return (fracErrorSelector, cursor, 0, 0);
                    }
                    fracValue = fracValueTmp;
                }
                // Frac value inherits its sign from the coefficient.
                if (fracValue < 0) {
                    return (MalformedDecimalPoint.selector, cursor, 0, 0);
                }
                if (isNegative) {
                    fracValue = -fracValue;
                }

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
                    // exponent is non positive here.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    uint256 scale = uint256(-exponent);
                    // 67 is the maximum number of fractional digits we can
                    // rescale by without overflowing. The coefficient is at
                    // most int224 (~6.7e66), and the rescaled product
                    // (coefficient * 10^scale) must fit in int256 (~5.8e76).
                    // Beyond 67 digits the multiplication would overflow
                    // int256 for any non-trivial coefficient.
                    if (scale > 67) {
                        return (ParseDecimalPrecisionLoss.selector, cursor, 0, 0);
                    }
                    scale = 10 ** scale;
                    // scale [1, 1e67]
                    // forge-lint: disable-next-line(unsafe-typecast)
                    int256 rescaledIntValue = signedCoefficient * int256(scale);
                    // Check 1: the multiplication overflowed int256.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    bool mulDidOverflow = rescaledIntValue / int256(scale) != signedCoefficient;
                    // Check 2: the rescaled value exceeds int224 precision,
                    // so it cannot be packed losslessly into a Float.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    bool mulDidTruncate = int224(rescaledIntValue) != rescaledIntValue;
                    if (mulDidOverflow || mulDidTruncate) {
                        return (ParseDecimalPrecisionLoss.selector, cursor, 0, 0);
                    }
                    signedCoefficient = rescaledIntValue + fracValue;
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
                    cursor = LibParseChar.skipMask(cursor, end, CMASK_NEGATIVE_SIGN);
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
                    if (eErrorSelector != 0) {
                        return (eErrorSelector, cursor, 0, 0);
                    }
                    eValue = eValueTmp;
                }

                {
                    int256 newExponent = exponent + eValue;
                    if ((eValue > 0 && newExponent < exponent) || (eValue < 0 && newExponent > exponent)) {
                        return (ExponentOverflow.selector, cursor, 0, 0);
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

    /// Folds each `,ddd` group at `cursor` into `signedCoefficient`, stopping
    /// at the first comma that is not followed by exactly three digits.
    function parseCommaGroups(uint256 cursor, uint256 end, bool isNegative, int256 signedCoefficient)
        private
        pure
        returns (bytes4, uint256, int256)
    {
        unchecked {
            while (
                LibParseChar.isMask(cursor, end, CMASK_COMMA) == 1
                    && LibParseChar.skipMask(cursor + 1, end, CMASK_NUMERIC_0_9) == cursor + 4
            ) {
                // Three digits cannot fail to parse.
                //slither-disable-next-line unused-return
                (, uint256 group) = LibParseDecimal.unsafeDecimalStringToInt(cursor + 1, cursor + 4);
                cursor += 4;
                // forge-lint: disable-next-line(unsafe-typecast)
                int256 signedGroup = int256(group);
                if (isNegative) {
                    if (signedCoefficient < (type(int256).min + signedGroup) / 1000) {
                        return (ParseDecimalOverflow.selector, cursor, 0);
                    }
                    signedCoefficient = signedCoefficient * 1000 - signedGroup;
                } else {
                    if (signedCoefficient > (type(int256).max - signedGroup) / 1000) {
                        return (ParseDecimalOverflow.selector, cursor, 0);
                    }
                    signedCoefficient = signedCoefficient * 1000 + signedGroup;
                }
            }
            return (0, cursor, signedCoefficient);
        }
    }

    /// @notice Parses a decimal float from a string. This a high-level wrapper
    /// around `parseDecimalFloatInline` that handles string memory layout and
    /// returns a packed `Float` amenable to subsequent operations with
    /// `LibDecimalFloat`. A comma is reported as excess characters.
    /// @param str The string to parse.
    /// @return The error selector if an error occurred, otherwise 0.
    /// @return The parsed `Float` if no error occurred, otherwise zero.
    function parseDecimalFloat(string memory str) internal pure returns (bytes4, Float) {
        return parseDecimalFloat(str, false);
    }

    /// @notice As `parseDecimalFloat(string)`, optionally accepting commas as
    /// thousands separators per `parseDecimalFloatInline`. A comma outside
    /// that grouping is reported as excess characters.
    /// @param str The string to parse.
    /// @param commas Whether to accept commas as thousands separators.
    /// @return The error selector if an error occurred, otherwise 0.
    /// @return The parsed `Float` if no error occurred, otherwise zero.
    function parseDecimalFloat(string memory str, bool commas) internal pure returns (bytes4, Float) {
        uint256 start;
        uint256 end;
        assembly {
            start := add(str, 0x20)
            end := add(start, mload(str))
        }
        (bytes4 errorSelector, uint256 cursor, int256 signedCoefficient, int256 exponent) =
            parseDecimalFloatInline(start, end, commas);
        if (errorSelector == 0) {
            if (cursor == end) {
                // If we consumed the whole string, we can return the parsed value.
                // packLossy handles the two exponent-overflow directions differently:
                // - Positive exponent overflow (e.g. 1e2147483648) has no meaningful
                //   approximation, so packLossy reverts with ExponentOverflow.
                // - Negative exponent overflow is first met by shedding trailing
                //   digits of the coefficient to lift the exponent to int32.min
                //   (e.g. 10e-2147483649 is 1e-2147483648, which packs
                //   losslessly). Only a number that genuinely rounds to zero
                //   (e.g. 1e-2147483649) makes packLossy return
                //   (FLOAT_ZERO, false), and we report ParseDecimalPrecisionLoss.
                (Float result, bool lossless) = LibDecimalFloat.packLossy(signedCoefficient, exponent);
                if (!lossless) {
                    return (ParseDecimalPrecisionLoss.selector, Float.wrap(0));
                } else {
                    return (0, result);
                }
            } else {
                // If we didn't consume the whole string, it is malformed.
                return (ParseDecimalFloatExcessCharacters.selector, Float.wrap(0));
            }
        } else {
            // If we encountered an error, we return the error selector and a
            // zero float.
            return (errorSelector, Float.wrap(0));
        }
    }
}
