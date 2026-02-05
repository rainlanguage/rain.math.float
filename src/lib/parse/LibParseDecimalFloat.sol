// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibParseChar} from "rain.string/lib/parse/LibParseChar.sol";
import {
    CMASK_NUMERIC_0_9,
    CMASK_NEGATIVE_SIGN,
    CMASK_E_NOTATION,
    CMASK_ZERO,
    CMASK_DECIMAL_POINT
} from "rain.string/lib/parse/LibParseCMask.sol";
import {LibParseDecimal} from "rain.string/lib/parse/LibParseDecimal.sol";
import {MalformedExponentDigits, ParseDecimalPrecisionLoss, MalformedDecimalPoint} from "../../error/ErrParse.sol";
import {ParseEmptyDecimalString} from "rain.string/error/ErrParse.sol";
import {LibDecimalFloat, Float} from "../LibDecimalFloat.sol";
import {ParseDecimalFloatExcessCharacters} from "../../error/ErrParse.sol";

/// @title LibParseDecimalFloat
/// @notice Library for parsing decimal floating point numbers from strings.
/// Not particularly gas efficient as it is intended for off-chain use cases.
/// Main use case is ensuring consistent behaviour across all offchain
/// implementations by standardizing in Solidity.
library LibParseDecimalFloat {
    /// @notice Parses a decimal float from a substring defined by [start, end).
    /// @param start The starting index of the substring (inclusive).
    /// @param end The ending index of the substring (exclusive).
    /// @return errorSelector The error selector if an error occurred, otherwise
    /// 0.
    /// @return cursor The position in the string after parsing.
    /// @return signedCoefficient The signed coefficient of the parsed decimal
    /// float.
    /// @return exponent The exponent of the parsed decimal float.
    function parseDecimalFloatInline(uint256 start, uint256 end)
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
                    if (scale > 67) {
                        return (ParseDecimalPrecisionLoss.selector, cursor, 0, 0);
                    }
                    scale = 10 ** scale;
                    // scale [0, 1e67]
                    // forge-lint: disable-next-line(unsafe-typecast)
                    int256 rescaledIntValue = signedCoefficient * int256(scale);
                    // scale [0, 1e67]
                    // forge-lint: disable-next-line(unsafe-typecast)
                    bool mulDidOverflow = rescaledIntValue / int256(scale) != signedCoefficient;
                    // truncation is intentional as it is part of the check here.
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
                cursor = LibParseChar.skipMask(cursor, end, CMASK_NEGATIVE_SIGN);
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

                exponent += eValue;
            }

            if (signedCoefficient == 0) {
                // Normalize zero to have exponent zero. This ensures that parsed
                // floats follow the behaviour of packed floats.
                exponent = 0;
            }
        }
    }

    /// @notice Parses a decimal float from a string. This a high-level wrapper
    /// around `parseDecimalFloatInline` that handles string memory layout and
    /// returns a packed `Float` amenable to subsequent operations with
    /// `LibDecimalFloat`.
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
        if (errorSelector == 0) {
            if (cursor == end) {
                // If we consumed the whole string, we can return the parsed value.
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
