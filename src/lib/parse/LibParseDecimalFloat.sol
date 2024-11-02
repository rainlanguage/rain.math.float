// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 thedavidmeister
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
import {LibDecimalFloat} from "../LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "../implementation/LibDecimalFloatImplementation.sol";

library LibParseDecimalFloat {
    function parseDecimalFloatPacked(uint256 start, uint256 end) internal pure returns (bytes4, uint256, uint256) {
        (bytes4 errorSelector, uint256 cursor, int256 signedCoefficient, int256 exponent) =
            parseDecimalFloat(start, end);
        if (errorSelector != 0) {
            return (errorSelector, cursor, 0);
        }

        // Prenormalize signed coefficients that are smaller than their
        // normalized form at parse time, as this can save runtime gas that would
        // be needed to normalize the value at runtime.
        // We only do normalization that will scale up, to avoid causing
        // unneccessary precision loss.
        if (-1e37 < signedCoefficient && signedCoefficient < 1e37) {
            (signedCoefficient, exponent) = LibDecimalFloatImplementation.normalize(signedCoefficient, exponent);
        }

        uint256 packedFloat = LibDecimalFloat.pack(signedCoefficient, exponent);

        (int256 unpackedSignedCoefficient, int256 unpackedExponent) = LibDecimalFloat.unpack(packedFloat);
        if (unpackedSignedCoefficient != signedCoefficient || unpackedExponent != exponent) {
            return (ParseDecimalPrecisionLoss.selector, cursor, 0);
        }

        return (0, cursor, packedFloat);
    }

    function parseDecimalFloat(uint256 start, uint256 end)
        internal
        pure
        returns (bytes4 errorSelector, uint256 cursor, int256 signedCoefficient, int256 exponent)
    {
        unchecked {
            cursor = start;
            cursor = LibParseChar.skipMask(cursor, end, CMASK_NEGATIVE_SIGN);
            {
                uint256 intStart = cursor;
                cursor = LibParseChar.skipMask(cursor, end, CMASK_NUMERIC_0_9);
                if (cursor == intStart) {
                    return (ParseEmptyDecimalString.selector, 0, 0, 0);
                }
            }
            {
                (bytes4 signedCoefficientErrorSelector, int256 signedCoefficientTmp) =
                    LibParseDecimal.unsafeDecimalStringToSignedInt(start, cursor);
                if (signedCoefficientErrorSelector != 0) {
                    return (signedCoefficientErrorSelector, 0, 0, 0);
                }
                signedCoefficient = signedCoefficientTmp;
            }

            int256 fracValue = int256(LibParseChar.isMask(cursor, end, CMASK_DECIMAL_POINT));
            if (fracValue != 0) {
                cursor++;
                uint256 fracStart = cursor;
                cursor = LibParseChar.skipMask(cursor, end, CMASK_NUMERIC_0_9);
                if (cursor == fracStart) {
                    return (MalformedDecimalPoint.selector, 0, 0, 0);
                }
                // Trailing zeros are allowed in fractional literals but should
                // not be counted in the precision.
                uint256 nonZeroCursor = cursor;
                while (LibParseChar.isMask(nonZeroCursor - 1, end, CMASK_ZERO) == 1) {
                    nonZeroCursor--;
                }

                {
                    (bytes4 fracErrorSelector, int256 fracValueTmp) =
                        LibParseDecimal.unsafeDecimalStringToSignedInt(fracStart, nonZeroCursor);
                    if (fracErrorSelector != 0) {
                        return (fracErrorSelector, 0, 0, 0);
                    }
                    fracValue = fracValueTmp;
                }
                // Frac value inherits its sign from the coefficient.
                if (fracValue < 0) {
                    return (MalformedDecimalPoint.selector, 0, 0, 0);
                }
                if (signedCoefficient < 0) {
                    fracValue = -fracValue;
                }

                // We want to _decrease_ the exponent by the number of digits in the
                // fractional part.
                exponent = int256(fracStart) - int256(nonZeroCursor);
                uint256 scale = uint256(-exponent);
                if (scale >= 77 && signedCoefficient != 0) {
                    return (ParseDecimalPrecisionLoss.selector, 0, 0, 0);
                }
                scale = 10 ** scale;
                int256 rescaledIntValue = signedCoefficient * int256(scale);
                if (rescaledIntValue / int256(scale) != signedCoefficient) {
                    return (ParseDecimalPrecisionLoss.selector, 0, 0, 0);
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
                        return (MalformedExponentDigits.selector, 0, 0, 0);
                    }
                }

                {
                    (bytes4 eErrorSelector, int256 eValueTmp) =
                        LibParseDecimal.unsafeDecimalStringToSignedInt(eStart, cursor);
                    if (eErrorSelector != 0) {
                        return (eErrorSelector, 0, 0, 0);
                    }
                    eValue = eValueTmp;
                }

                exponent += eValue;
            }
        }
    }
}
