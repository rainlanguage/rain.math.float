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
} from "../../src/error/ErrParse.sol";
import {ParseEmptyDecimalString} from "rain-string-0.3.9/src/error/ErrParse.sol";
import {Float} from "../../src/lib/LibDecimalFloat.sol";
import {ExponentOverflow} from "../../src/error/ErrDecimalFloat.sol";

/// `LibParseDecimalFloat` verbatim from
/// `src/lib/parse/LibParseDecimalFloat.sol` at ff6d70c (main), before #310's
/// parse change, with `LibDecimalFloat.packLossy` and `FLOAT_ZERO` copied from
/// the same commit as private, so it calls nothing on the live library.
/// Equivalence tests only.
/// EQUIVALENCE BASELINE ONLY, NEVER A VALUE ORACLE: agreeing with it says
/// nothing about a value. Expected values come from `LibTestDecimalLiteral`.
library LibParseDecimalFloatPr321 {
    /// A zero valued float.
    Float private constant FLOAT_ZERO = Float.wrap(0);

    /// @notice Parses a decimal float from a substring defined by [start, end).
    /// A literal whose exponent is below int256.min has a non-zero coefficient
    /// and is smaller than every Float, so it is `ParseDecimalPrecisionLoss`,
    /// as `parseDecimalFloat` reports any literal smaller than every Float.
    /// An integer part past int256 returns its trailing zeros in the exponent,
    /// and a zero coefficient takes exponent digits of any size.
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
            cursor += LibParseChar.isMask(cursor, end, CMASK_NEGATIVE_SIGN);
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
                    // A nonempty digit run fails only past int256.
                    (signedCoefficientErrorSelector, cursor, signedCoefficientTmp, exponent) =
                        parseIntegerPastInt256(start, cursor, end);
                    if (signedCoefficientErrorSelector != 0) {
                        return (signedCoefficientErrorSelector, cursor, 0, 0);
                    }
                }
                signedCoefficient = signedCoefficientTmp;
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
                uint256 nonZeroCursor = cursor;
                while (LibParseChar.isMask(nonZeroCursor - 1, end, CMASK_ZERO) == 1) {
                    nonZeroCursor--;
                }

                // An all-zero fraction is the same literal as no fraction.
                if (nonZeroCursor != fracStart) {
                    bytes4 fracErrorSelector;
                    (fracErrorSelector, fracValue) =
                        LibParseDecimal.unsafeDecimalStringToSignedInt(fracStart, nonZeroCursor);
                    if (fracErrorSelector != 0) {
                        return (fracErrorSelector, cursor, 0, 0);
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
                        // exponent is negative here.
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
                        // scale [10, 1e67]
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
                    // Exponent digits fail only past int256, which is no
                    // Float unless the coefficient is zero. The failed parse
                    // leaves eValueTmp zero.
                    if (eErrorSelector != 0) {
                        if (signedCoefficient != 0) {
                            return (eErrorSelector, cursor, 0, 0);
                        }
                    }
                    eValue = eValueTmp;
                }

                {
                    // The sum wraps exactly when it moves against eValue's
                    // sign. A fraction makes exponent negative and trailing
                    // zeros past int256 make it positive, so either way can
                    // wrap: below int256.min the value is smaller than every
                    // Float, above int256.max it is larger than every Float.
                    int256 newExponent = exponent + eValue;
                    if ((newExponent < exponent) != (eValue < 0)) {
                        return
                            (eValue < 0 ? ParseDecimalPrecisionLoss.selector : ExponentOverflow.selector, cursor, 0, 0);
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

    /// @notice Parses an integer part past int256, `[start, intEnd)` with any
    /// sign, by moving its trailing zeros into the exponent. With significant
    /// digits still past int256 it is `ParseDecimalOverflow`, and a nonzero
    /// fraction digit after it is `ParseDecimalPrecisionLoss`: either needs a
    /// coefficient past int256, so neither is a Float. An all-zero fraction
    /// is consumed here.
    /// @param start The start of the integer part, at its sign if any.
    /// @param intEnd The end of the integer part's digits, which hold a
    /// nonzero digit.
    /// @param end The end of the whole string.
    /// @return errorSelector The error selector if an error occurred,
    /// otherwise 0.
    /// @return cursor The position after the integer part and any fraction.
    /// @return signedCoefficient The integer part without its trailing zeros.
    /// @return exponent The number of trailing zeros.
    function parseIntegerPastInt256(uint256 start, uint256 intEnd, uint256 end)
        private
        pure
        returns (bytes4 errorSelector, uint256 cursor, int256 signedCoefficient, int256 exponent)
    {
        unchecked {
            uint256 significantEnd = intEnd;
            while (LibParseChar.isMask(significantEnd - 1, end, CMASK_ZERO) == 1) {
                significantEnd--;
            }
            (errorSelector, signedCoefficient) = LibParseDecimal.unsafeDecimalStringToSignedInt(start, significantEnd);
            cursor = intEnd;
            if (errorSelector != 0) {
                return (errorSelector, cursor, 0, 0);
            }
            if (LibParseChar.isMask(cursor, end, CMASK_DECIMAL_POINT) == 1) {
                cursor++;
                uint256 fracStart = cursor;
                cursor = LibParseChar.skipMask(cursor, end, CMASK_NUMERIC_0_9);
                if (cursor == fracStart) {
                    return (MalformedDecimalPoint.selector, cursor, 0, 0);
                }
                if (LibParseChar.skipMask(fracStart, cursor, CMASK_ZERO) != cursor) {
                    return (ParseDecimalPrecisionLoss.selector, cursor, 0, 0);
                }
            }
            // The zero count is bounded by memory.
            // forge-lint: disable-next-line(unsafe-typecast)
            exponent = int256(intEnd - significantEnd);
        }
    }

    /// @notice Parses a decimal float from a string. This a high-level wrapper
    /// around `parseDecimalFloatInline` that handles string memory layout and
    /// returns a packed `Float` amenable to subsequent operations with
    /// `LibDecimalFloat`. A literal larger in magnitude than every Float is
    /// `ExponentOverflow`: a revert from packing, or the selector when its
    /// exponent is past int256. Any other literal that is not exactly a Float, one
    /// smaller than every Float included, returns `ParseDecimalPrecisionLoss`.
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
                (Float result, bool lossless) = packLossy(signedCoefficient, exponent);
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

    /// Pack a signed coefficient and exponent into a single `Float`, returning
    /// the Float closest to the value that does not exceed its magnitude.
    ///
    /// A coefficient past int224 sheds digits, truncating toward zero, until it
    /// fits. If the result fits ten times over, the int224 bound one exponent
    /// down is closer (`2^223` packs as int224.max at the same exponent, not
    /// `2^223 / 10` at the next) and is returned instead. An exponent below the
    /// int32 floor sheds digits up to it, and is `FLOAT_ZERO` once every digit
    /// is gone. An exponent above the ceiling is lowered by multiplying the
    /// coefficient by ten, which is exact; `ExponentOverflow` when int224 has no
    /// headroom for that.
    /// @param signedCoefficient The signed coefficient of the floating point
    /// representation.
    /// @param exponent The exponent of the floating point representation.
    /// @return float The packed representation of the signed coefficient and
    /// exponent.
    /// @return lossless True iff every digit shed was zero, so the packed value
    /// equals the input.
    function packLossy(int256 signedCoefficient, int256 exponent) private pure returns (Float float, bool lossless) {
        unchecked {
            int256 initialSignedCoefficient = signedCoefficient;
            int256 initialExponent = exponent;

            // truncation here is intentional if it happens as that is what we
            // are testing for.
            // forge-lint: disable-next-line(unsafe-typecast)
            bool fits = int224(signedCoefficient) == signedCoefficient;

            if (!fits) {
                // int224.max is ~1.35e67, so 1e75 or more must shed at least 8
                // digits and 1e72 or more at least 5. Cut those in one division
                // to skip loop iterations. `/` truncates toward zero, so the
                // result never exceeds the magnitude.
                if (signedCoefficient / 1e72 != 0) {
                    if (signedCoefficient / 1e75 != 0) {
                        signedCoefficient /= 1e8;
                        exponent += 8;
                    } else {
                        signedCoefficient /= 1e5;
                        exponent += 5;
                    }
                }

                // truncation here is intentional if it happens as that is what we
                // are testing for.
                // forge-lint: disable-next-line(unsafe-typecast)
                while (int224(signedCoefficient) != signedCoefficient) {
                    signedCoefficient /= 10;
                    ++exponent;
                }

                // Before the last division the coefficient did not fit at
                // `exponent - 1`, so |value| >= int224.max * 10^(exponent - 1).
                // If |c| <= int224.max / 10 then c * 10 <= int224.max - 7, so
                // that bound is closer than c and still does not exceed the
                // value; otherwise c * 10 > int224.max and c is closer.
                // Adding tenFold maps [-tenFold, tenFold] onto [0, 2 * tenFold]
                // and anything outside wraps huge as uint256: one compare for
                // both signs, since int224.max / 10 == 2^223 / 10.
                int256 tenFold = type(int224).max / 10;
                // forge-lint: disable-next-line(unsafe-typecast)
                if (uint256(signedCoefficient + tenFold) <= uint256(tenFold + tenFold)) {
                    int256 boundExponent = exponent - 1;
                    // Below the int32 floor the bound is skipped and the floor
                    // path below keeps shedding.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    if (int32(boundExponent) == boundExponent) {
                        int256 bound = type(int224).max;
                        uint256 boundMask = type(uint224).max;
                        assembly ("memory-safe") {
                            // sar(255, c) is all ones when c < 0, so the xor
                            // gives ~int224.max == int224.min for a negative
                            // value and int224.max otherwise, without a branch.
                            bound := xor(sar(255, signedCoefficient), bound)
                            float := or(and(bound, boundMask), shl(0xe0, boundExponent))
                        }
                        // The literal is the bool this function returns, not a condition operand.
                        //forge-lint: disable-next-line(boolean-cst)
                        return (float, false);
                    }
                }
            } else {
                if (signedCoefficient == 0) {
                    // The literal is the bool this function returns, not a condition operand.
                    //forge-lint: disable-next-line(boolean-cst)
                    return (FLOAT_ZERO, true);
                }
            }

            // truncation here is intentional if it happens as that is what we
            // are testing for.
            // forge-lint: disable-next-line(unsafe-typecast)
            if (int32(exponent) != exponent) {
                // Shedding raises the exponent by at most ten digits, so an
                // exponent past the ceiling started positive, and one that
                // started positive and is out of range is past the ceiling,
                // or wrapped through int256.max by the unchecked shedding.
                if (initialExponent > 0) {
                    // Lower the exponent by multiplying the coefficient by ten
                    // per step, which is exact, while int224 has the headroom.
                    // A coefficient shed to fit int224 has none, and a non-zero
                    // int224 has at most 68 digits so an excess of 68 or more
                    // never has it. Either way the magnitude exceeds every
                    // representable Float.
                    int256 excess = exponent - type(int32).max;
                    if (!fits || excess > 67) {
                        revert ExponentOverflow(initialSignedCoefficient, initialExponent);
                    }
                    // excess is in [1, 67] so 10 ** excess fits int256 and the
                    // casts cannot truncate.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    int256 scale = int256(10 ** uint256(excess));
                    // Nothing was shed, so the initial coefficient is the one to
                    // lift.
                    if (
                        initialSignedCoefficient > type(int224).max / scale
                            || initialSignedCoefficient < type(int224).min / scale
                    ) {
                        revert ExponentOverflow(initialSignedCoefficient, initialExponent);
                    }
                    signedCoefficient = initialSignedCoefficient * scale;
                    exponent = type(int32).max;
                } else {
                    // The exponent is below the int32 floor. Every division of the
                    // coefficient by ten raises the exponent by one, so the
                    // shortfall is exactly the number of digits to shed. The
                    // coefficient fits int224 here, so it has at most 68 decimal
                    // digits and a shortfall of 68 or more sheds every one of
                    // them: that is zero without computing it. `exponent` is
                    // negative here and below int32.min, so the subtraction cannot
                    // overflow and the shortfall is positive.
                    int256 shortfall = int256(type(int32).min) - exponent;
                    if (shortfall > 67) {
                        // The literal is the bool this function returns, not a condition operand.
                        //forge-lint: disable-next-line(boolean-cst)
                        return (FLOAT_ZERO, false);
                    }
                    // shortfall is in [1, 67] so 10 ** shortfall fits int256 and the
                    // casts cannot truncate.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    signedCoefficient /= int256(10 ** uint256(shortfall));
                    if (signedCoefficient == 0) {
                        // Every digit was shed: the value is smaller in magnitude
                        // than any representable Float, so this is the underflow
                        // zero and it is not a lossless conversion.
                        // The literal is the bool this function returns, not a condition operand.
                        //forge-lint: disable-next-line(boolean-cst)
                        return (FLOAT_ZERO, false);
                    }
                    exponent = type(int32).min;
                }
            }

            // Lossless iff every digit shed was a zero, which is iff the
            // original coefficient is an exact multiple of ten to the number of
            // digits shed. Shedding only raises the exponent and lifting only
            // lowers it, and never both, so an exponent at or below the initial
            // one shed nothing. Otherwise the number shed is the rise, which is
            // in [1, 76] for any non-zero result (an int256 has at most 77
            // digits and at least one survived), so the power fits int256.
            if (exponent <= initialExponent) {
                // The literal is the bool this function returns, not a condition operand.
                //forge-lint: disable-next-line(boolean-cst)
                lossless = true;
            } else {
                // The rise is in [1, 76] so the casts cannot truncate.
                // forge-lint: disable-next-line(unsafe-typecast)
                lossless = initialSignedCoefficient % int256(10 ** uint256(exponent - initialExponent)) == 0;
            }

            // Need a mask to zero out the bits that could be set to 1 if the
            // coefficient is negative.
            uint256 mask = type(uint224).max;
            assembly ("memory-safe") {
                float := or(and(signedCoefficient, mask), shl(0xe0, exponent))
            }
        }
    }
}
