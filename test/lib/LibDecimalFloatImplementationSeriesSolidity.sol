// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    LibDecimalFloatImplementation,
    POW_FIXED_ONE,
    POW_FIXED_LN10,
    POW_FIXED_SQRT_ONE,
    POW_FIXED_TWO_SQRT_ONE,
    POW_FIXED_ONE_ODD_INVERSE,
    EXP10_THRESHOLD_1,
    EXP10_THRESHOLD_2,
    EXP10_THRESHOLD_3,
    EXP10_THRESHOLD_4,
    EXP10_THRESHOLD_5,
    EXP10_THRESHOLD_6,
    EXP10_THRESHOLD_7,
    EXP10_THRESHOLD_8,
    EXP10_THRESHOLD_9,
    EXP10_THRESHOLD_10,
    EXP10_THRESHOLD_11,
    EXP10_THRESHOLD_12,
    EXP10_THRESHOLD_13,
    EXP10_THRESHOLD_14,
    EXP10_THRESHOLD_15,
    EXP10_THRESHOLD_16,
    EXP10_STEP_1,
    EXP10_STEP_2,
    EXP10_STEP_3,
    EXP10_STEP_4,
    EXP10_STEP_5,
    EXP10_STEP_6,
    EXP10_STEP_7,
    EXP10_STEP_8,
    EXP10_STEP_9,
    EXP10_STEP_10,
    EXP10_STEP_11,
    EXP10_STEP_12,
    EXP10_STEP_13,
    EXP10_STEP_14,
    EXP10_STEP_15,
    EXP10_STEP_16,
    EXP10_HORNER_9,
    EXP10_HORNER_8,
    EXP10_HORNER_7,
    EXP10_HORNER_6,
    EXP10_HORNER_5,
    EXP10_HORNER_4,
    EXP10_HORNER_3,
    EXP10_HORNER_2
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Log10RatioRelativeSumTooSmall} from "src/error/ErrDecimalFloat.sol";

/// `log10Ratio` and `exp10Fixed` with the library's unrolled algorithm (seven
/// atanh terms, the 1e25 split of z^2, every `mulDivFixed` written out in place,
/// the same constants) and every assembly block written as plain Solidity.
/// Gas comparison and equivalence tests only, isolating the assembly.
library LibDecimalFloatImplementationSeriesSolidity {
    // slither-disable-start divide-before-multiply
    function log10Ratio(uint256 a, uint256 b, bool relative) internal pure returns (int256, int256) {
        bool below = a < b;
        uint256 difference = below ? b - a : a - b;
        uint256 sum = a + b;
        uint256 z;
        int256 exponent = -50;
        if (relative) {
            if (sum < POW_FIXED_ONE) {
                revert Log10RatioRelativeSumTooSmall(a, b);
            }
            z = LibDecimalFloatImplementation.mulDiv(difference, POW_FIXED_ONE, sum);
            // Scale the difference by the largest power of ten that keeps it
            // within int256.max, as maximizeFull does.
            unchecked {
                if (difference != 0) {
                    if (difference <= uint256(type(int256).max) / 1e64) {
                        difference *= 1e64;
                        exponent -= 64;
                    }
                    if (difference <= uint256(type(int256).max) / 1e32) {
                        difference *= 1e32;
                        exponent -= 32;
                    }
                    if (difference <= uint256(type(int256).max) / 1e16) {
                        difference *= 1e16;
                        exponent -= 16;
                    }
                    if (difference <= uint256(type(int256).max) / 1e8) {
                        difference *= 1e8;
                        exponent -= 8;
                    }
                    if (difference <= uint256(type(int256).max) / 1e4) {
                        difference *= 1e4;
                        exponent -= 4;
                    }
                    if (difference <= uint256(type(int256).max) / 1e2) {
                        difference *= 1e2;
                        exponent -= 2;
                    }
                    if (difference <= uint256(type(int256).max) / 10) {
                        difference *= 10;
                        exponent -= 1;
                    }
                }
            }
        } else {
            z = LibDecimalFloatImplementation.mulDiv(difference, POW_FIXED_ONE, sum);
        }
        uint256 series;
        uint256 inverse = POW_FIXED_ONE_ODD_INVERSE;
        // Wrapping is the written-out mulDiv's own mod 2^256 arithmetic, and
        // the library proves every other step fits a word.
        unchecked {
            uint256 u = z / POW_FIXED_SQRT_ONE;
            uint256 v = z % POW_FIXED_SQRT_ONE;
            uint256 zSquared = u * u + (u * v * POW_FIXED_TWO_SQRT_ONE + v * v) / POW_FIXED_ONE;
            series = POW_FIXED_ONE + zSquared / 3;
            uint256 mm;
            uint256 prod0;
            uint256 remainder;
            uint256 term;
            mm = mulmod(zSquared, zSquared, type(uint256).max);
            prod0 = zSquared * zSquared;
            remainder = mulmod(zSquared, zSquared, POW_FIXED_ONE);
            term =
                (((prod0 - remainder) >> 50)
                            | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            series += term / 5;
            mm = mulmod(term, zSquared, type(uint256).max);
            prod0 = term * zSquared;
            remainder = mulmod(term, zSquared, POW_FIXED_ONE);
            term =
                (((prod0 - remainder) >> 50)
                            | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            series += term / 7;
            term = term * zSquared / POW_FIXED_ONE;
            series += term / 9;
            term = term * zSquared / POW_FIXED_ONE;
            series += term / 11;
            term = term * zSquared / POW_FIXED_ONE;
            series += term / 13;
            term = term * zSquared / POW_FIXED_ONE;
            series += term / 15;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedCoefficient = int256(
            LibDecimalFloatImplementation.mulDiv(
                difference, LibDecimalFloatImplementation.mulDiv(series, 2 * POW_FIXED_ONE, POW_FIXED_LN10), sum
            )
        );
        return (below ? -signedCoefficient : signedCoefficient, exponent);
    }

    // slither-disable-end divide-before-multiply

    //slither-disable-next-line cyclomatic-complexity
    function exp10Fixed(uint256 x) internal pure returns (uint256 result) {
        uint256 inverse = POW_FIXED_ONE_ODD_INVERSE;
        // As in log10Ratio, and x only loses a threshold it is at least.
        unchecked {
            uint256 mm;
            uint256 prod0;
            uint256 remainder;
            result = POW_FIXED_ONE;
            if (x >= EXP10_THRESHOLD_1) {
                x -= EXP10_THRESHOLD_1;
                result = EXP10_STEP_1;
            }
            if (x >= EXP10_THRESHOLD_2) {
                x -= EXP10_THRESHOLD_2;
                mm = mulmod(result, EXP10_STEP_2, type(uint256).max);
                prod0 = result * EXP10_STEP_2;
                remainder = mulmod(result, EXP10_STEP_2, POW_FIXED_ONE);
                result =
                    (((prod0 - remainder) >> 50)
                                | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            }
            if (x >= EXP10_THRESHOLD_3) {
                x -= EXP10_THRESHOLD_3;
                mm = mulmod(result, EXP10_STEP_3, type(uint256).max);
                prod0 = result * EXP10_STEP_3;
                remainder = mulmod(result, EXP10_STEP_3, POW_FIXED_ONE);
                result =
                    (((prod0 - remainder) >> 50)
                                | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            }
            if (x >= EXP10_THRESHOLD_4) {
                x -= EXP10_THRESHOLD_4;
                mm = mulmod(result, EXP10_STEP_4, type(uint256).max);
                prod0 = result * EXP10_STEP_4;
                remainder = mulmod(result, EXP10_STEP_4, POW_FIXED_ONE);
                result =
                    (((prod0 - remainder) >> 50)
                                | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            }
            if (x >= EXP10_THRESHOLD_5) {
                x -= EXP10_THRESHOLD_5;
                mm = mulmod(result, EXP10_STEP_5, type(uint256).max);
                prod0 = result * EXP10_STEP_5;
                remainder = mulmod(result, EXP10_STEP_5, POW_FIXED_ONE);
                result =
                    (((prod0 - remainder) >> 50)
                                | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            }
            if (x >= EXP10_THRESHOLD_6) {
                x -= EXP10_THRESHOLD_6;
                mm = mulmod(result, EXP10_STEP_6, type(uint256).max);
                prod0 = result * EXP10_STEP_6;
                remainder = mulmod(result, EXP10_STEP_6, POW_FIXED_ONE);
                result =
                    (((prod0 - remainder) >> 50)
                                | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            }
            if (x >= EXP10_THRESHOLD_7) {
                x -= EXP10_THRESHOLD_7;
                mm = mulmod(result, EXP10_STEP_7, type(uint256).max);
                prod0 = result * EXP10_STEP_7;
                remainder = mulmod(result, EXP10_STEP_7, POW_FIXED_ONE);
                result =
                    (((prod0 - remainder) >> 50)
                                | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            }
            if (x >= EXP10_THRESHOLD_8) {
                x -= EXP10_THRESHOLD_8;
                mm = mulmod(result, EXP10_STEP_8, type(uint256).max);
                prod0 = result * EXP10_STEP_8;
                remainder = mulmod(result, EXP10_STEP_8, POW_FIXED_ONE);
                result =
                    (((prod0 - remainder) >> 50)
                                | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            }
            if (x >= EXP10_THRESHOLD_9) {
                x -= EXP10_THRESHOLD_9;
                mm = mulmod(result, EXP10_STEP_9, type(uint256).max);
                prod0 = result * EXP10_STEP_9;
                remainder = mulmod(result, EXP10_STEP_9, POW_FIXED_ONE);
                result =
                    (((prod0 - remainder) >> 50)
                                | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            }
            if (x >= EXP10_THRESHOLD_10) {
                x -= EXP10_THRESHOLD_10;
                mm = mulmod(result, EXP10_STEP_10, type(uint256).max);
                prod0 = result * EXP10_STEP_10;
                remainder = mulmod(result, EXP10_STEP_10, POW_FIXED_ONE);
                result =
                    (((prod0 - remainder) >> 50)
                                | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            }
            if (x >= EXP10_THRESHOLD_11) {
                x -= EXP10_THRESHOLD_11;
                mm = mulmod(result, EXP10_STEP_11, type(uint256).max);
                prod0 = result * EXP10_STEP_11;
                remainder = mulmod(result, EXP10_STEP_11, POW_FIXED_ONE);
                result =
                    (((prod0 - remainder) >> 50)
                                | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            }
            if (x >= EXP10_THRESHOLD_12) {
                x -= EXP10_THRESHOLD_12;
                mm = mulmod(result, EXP10_STEP_12, type(uint256).max);
                prod0 = result * EXP10_STEP_12;
                remainder = mulmod(result, EXP10_STEP_12, POW_FIXED_ONE);
                result =
                    (((prod0 - remainder) >> 50)
                                | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            }
            if (x >= EXP10_THRESHOLD_13) {
                x -= EXP10_THRESHOLD_13;
                mm = mulmod(result, EXP10_STEP_13, type(uint256).max);
                prod0 = result * EXP10_STEP_13;
                remainder = mulmod(result, EXP10_STEP_13, POW_FIXED_ONE);
                result =
                    (((prod0 - remainder) >> 50)
                                | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            }
            if (x >= EXP10_THRESHOLD_14) {
                x -= EXP10_THRESHOLD_14;
                mm = mulmod(result, EXP10_STEP_14, type(uint256).max);
                prod0 = result * EXP10_STEP_14;
                remainder = mulmod(result, EXP10_STEP_14, POW_FIXED_ONE);
                result =
                    (((prod0 - remainder) >> 50)
                                | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            }
            if (x >= EXP10_THRESHOLD_15) {
                x -= EXP10_THRESHOLD_15;
                mm = mulmod(result, EXP10_STEP_15, type(uint256).max);
                prod0 = result * EXP10_STEP_15;
                remainder = mulmod(result, EXP10_STEP_15, POW_FIXED_ONE);
                result =
                    (((prod0 - remainder) >> 50)
                                | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            }
            if (x >= EXP10_THRESHOLD_16) {
                x -= EXP10_THRESHOLD_16;
                mm = mulmod(result, EXP10_STEP_16, type(uint256).max);
                prod0 = result * EXP10_STEP_16;
                remainder = mulmod(result, EXP10_STEP_16, POW_FIXED_ONE);
                result =
                    (((prod0 - remainder) >> 50)
                                | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            }
            uint256 series = EXP10_HORNER_9;
            mm = mulmod(series, x, type(uint256).max);
            prod0 = series * x;
            remainder = mulmod(series, x, POW_FIXED_ONE);
            series =
                (((prod0 - remainder) >> 50)
                            | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            series = EXP10_HORNER_8 + series;
            mm = mulmod(series, x, type(uint256).max);
            prod0 = series * x;
            remainder = mulmod(series, x, POW_FIXED_ONE);
            series =
                (((prod0 - remainder) >> 50)
                            | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            series = EXP10_HORNER_7 + series;
            mm = mulmod(series, x, type(uint256).max);
            prod0 = series * x;
            remainder = mulmod(series, x, POW_FIXED_ONE);
            series =
                (((prod0 - remainder) >> 50)
                            | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            series = EXP10_HORNER_6 + series;
            mm = mulmod(series, x, type(uint256).max);
            prod0 = series * x;
            remainder = mulmod(series, x, POW_FIXED_ONE);
            series =
                (((prod0 - remainder) >> 50)
                            | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            series = EXP10_HORNER_5 + series;
            mm = mulmod(series, x, type(uint256).max);
            prod0 = series * x;
            remainder = mulmod(series, x, POW_FIXED_ONE);
            series =
                (((prod0 - remainder) >> 50)
                            | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            series = EXP10_HORNER_4 + series;
            mm = mulmod(series, x, type(uint256).max);
            prod0 = series * x;
            remainder = mulmod(series, x, POW_FIXED_ONE);
            series =
                (((prod0 - remainder) >> 50)
                            | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            series = EXP10_HORNER_3 + series;
            mm = mulmod(series, x, type(uint256).max);
            prod0 = series * x;
            remainder = mulmod(series, x, POW_FIXED_ONE);
            series =
                (((prod0 - remainder) >> 50)
                            | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            series = EXP10_HORNER_2 + series;
            mm = mulmod(series, x, type(uint256).max);
            prod0 = series * x;
            remainder = mulmod(series, x, POW_FIXED_ONE);
            series =
                (((prod0 - remainder) >> 50)
                            | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            series = POW_FIXED_LN10 + series;
            mm = mulmod(series, x, type(uint256).max);
            prod0 = series * x;
            remainder = mulmod(series, x, POW_FIXED_ONE);
            series =
                (((prod0 - remainder) >> 50)
                            | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
            series = POW_FIXED_ONE + series;
            mm = mulmod(result, series, type(uint256).max);
            prod0 = result * series;
            remainder = mulmod(result, series, POW_FIXED_ONE);
            result =
                (((prod0 - remainder) >> 50)
                            | ((mm - prod0 - (mm < prod0 ? 1 : 0) - (remainder > prod0 ? 1 : 0)) << 206)) * inverse;
        }
    }
}
