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
import {ParseDecimalOverflow, ParseEmptyDecimalString} from "rain.string/error/ErrParse.sol";
import {LibDecimalFloat, Float} from "../LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "../implementation/LibDecimalFloatImplementation.sol";
import {ParseDecimalFloatExcessCharacters} from "../../error/ErrParse.sol";

library LibParseDecimalFloat {
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
                exponent = int256(fracStart) - int256(nonZeroCursor);
                uint256 scale = uint256(-exponent);
                if (scale > 67 && signedCoefficient != 0) {
                    return (ParseDecimalPrecisionLoss.selector, cursor, 0, 0);
                }
                scale = 10 ** scale;
                int256 rescaledIntValue = signedCoefficient * int256(scale);
                if (
                    rescaledIntValue / int256(scale) != signedCoefficient
                        || int224(rescaledIntValue) != rescaledIntValue
                ) {
                    return (ParseDecimalPrecisionLoss.selector, cursor, 0, 0);
                }
                signedCoefficient = rescaledIntValue + fracValue;
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
        }
    }

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
                return (0, LibDecimalFloat.packLossless(signedCoefficient, exponent));
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
