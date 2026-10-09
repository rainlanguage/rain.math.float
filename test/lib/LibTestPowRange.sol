// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";
import {LibTranscendentalOracle, ORACLE_LN10, ORACLE_ONE} from "test/lib/LibTranscendentalOracle.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";
import {Float} from "src/lib/LibDecimalFloat.sol";
import {ExponentOverflow, ExponentUnderflow} from "src/error/ErrDecimalFloat.sol";

/// Where a result R lands against the Float range, given bounds on log10 R.
/// `Inside` demands a value, `Over` and `Under` the matching revert. At an
/// edge either is allowed, and `Unbounded` allows either revert.
enum PowRange {
    Inside,
    Over,
    Under,
    OverEdge,
    UnderEdge,
    Unbounded
}

/// @dev Bounds on log10 R are integers in units of 1e-66.
int256 constant UNIT_EXPONENT = -66;

/// @dev Each term is capped at 1e10, in units. Past every threshold, so a
/// capped term never decides wrongly: see `classify`.
uint256 constant CAP = 1e76;

/// @dev log10 of the least magnitude that packs past every Float,
/// (2^223 + 2) 10^int32.max, in units, truncated, from `bc -l` at scale 150.
int256 constant LOG10_OVERFLOW = 2147483714129689033067806532663773523561944969306343566050204712225323831345;

/// @dev log10 of the least positive Float, 10^int32.min, in units.
int256 constant LOG10_UNDERFLOW = int256(type(int32).min) * 1e66;

/// @dev log10(1 + E) <= E / ln 10 < 0.4343 E, and for E at most 1e-3,
/// -log10(1 - E) <= E / ((1 - E) ln 10) < 0.4348 E.
uint256 constant LOG10_UP_PER_E = 4343;
uint256 constant LOG10_DOWN_PER_E = 4348;

/// @dev The README's relative bound of pow10, and of pow before its 3N 1e-75,
/// 5.0000004e-41, as 50000004e-48.
uint256 constant RELATIVE_BOUND = 50000004;

/// @dev 2.18e-41 in units of 1e-57, past the under 2.175e-41 that pow10, and pow
/// for |b| under 1e10, may move log10 of their result by.
int256 constant THRESHOLD_SLACK = 218e14;

/// log10 |a| as its sign and whole + fraction 10^fractionExponent.
struct Log10 {
    bool negative;
    bool nearOne;
    uint256 whole;
    uint256 lowFraction;
    uint256 highFraction;
    int256 fractionExponent;
}

/// Decides where 10^x and |a|^b land in exact integer arithmetic over the
/// oracle, independent of the library under test. A result within relative E
/// of its true value 10^L has log10 R in [L - s, L + s'], s' = log10(1 + E)
/// and s = -log10(1 - E). Every bound below rounds outward.
library LibTestPowRange {
    /// x y 10^exponent in units, rounded up or down, capped at `CAP`.
    function units(uint256 x, uint256 y, int256 exponent, bool up) internal pure returns (uint256) {
        if (x == 0 || y == 0) {
            return 0;
        }
        int256 shift = exponent - UNIT_EXPONENT;
        if (shift >= 0) {
            (uint256 high, uint256 low) = Math.mul512(x, y);
            if (high != 0 || shift > 76) {
                return CAP;
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 scale = 10 ** uint256(shift);
            return low > CAP / scale ? CAP : low * scale;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 drop = uint256(-shift);
        if (drop > 77) {
            // x is below 1e78, so past 10^155 both factors' product leaves
            // under one unit.
            uint256 excess = drop - 77;
            if (excess > 77) {
                return up ? 1 : 0;
            }
            x = up ? Math.ceilDiv(x, 10 ** excess) : x / 10 ** excess;
            if (x == 0) {
                return 0;
            }
            drop = 77;
        }
        uint256 denominator = 10 ** drop;
        (uint256 productHigh,) = Math.mul512(x, y);
        // The quotient is at least 2^256 iff the high word is at least the
        // denominator.
        if (productHigh >= denominator) {
            return CAP;
        }
        return Math.min(Math.mulDiv(x, y, denominator, up ? Math.Rounding.Ceil : Math.Rounding.Floor), CAP);
    }

    /// `units` of coefficient 10^exponent, rounded down then up.
    function magnitudeUnits(uint256 magnitude, int256 exponent) internal pure returns (uint256, uint256) {
        return (units(magnitude, 1, exponent, false), units(magnitude, 1, exponent, true));
    }

    /// Where R lands for low <= log10 R <= high, in units. The thresholds are
    /// R >= (2^223 + 2) 10^int32.max overflows, R < 10^int32.min underflows.
    /// LOG10_OVERFLOW is truncated, so the true threshold is in
    /// (LOG10_OVERFLOW, LOG10_OVERFLOW + 1).
    ///
    /// A capped term only moves a bound to within `CAP` of zero while the
    /// other bound is past it, as no term is negative and |L| is capped too:
    /// `Inside` needs high - low under 4.3e75, `Over` a low past 2.1e75 and
    /// `Under` a high below -2.1e75, none of which a capped term allows.
    function classify(int256 low, int256 high) internal pure returns (PowRange) {
        if (low > LOG10_OVERFLOW) {
            return PowRange.Over;
        }
        if (high < LOG10_UNDERFLOW) {
            return PowRange.Under;
        }
        bool canOver = high > LOG10_OVERFLOW;
        bool canUnder = low < LOG10_UNDERFLOW;
        if (canOver && canUnder) {
            return PowRange.Unbounded;
        }
        if (canOver) {
            return PowRange.OverEdge;
        }
        if (canUnder) {
            return PowRange.UnderEdge;
        }
        return PowRange.Inside;
    }

    /// The signed bounds of L = sign magnitude, from magnitude bounds.
    function signed(bool negative, uint256 lowMagnitude, uint256 highMagnitude)
        internal
        pure
        returns (int256, int256)
    {
        // Both are at most CAP and so fit.
        // forge-lint: disable-next-line(unsafe-typecast)
        (int256 low, int256 high) = (int256(lowMagnitude), int256(highMagnitude));
        return negative ? (-high, -low) : (low, high);
    }

    /// Where pow10(x) lands. L is x itself, exact. E is pow10's 5.0000004e-41.
    function pow10Range(Float x) internal pure returns (PowRange) {
        (int256 signedCoefficient, int256 exponent) = unpack(x);
        (uint256 lowMagnitude, uint256 highMagnitude) =
            magnitudeUnits(LibTestExactDecimal.abs(signedCoefficient), exponent);
        (int256 low, int256 high) = signed(signedCoefficient < 0, lowMagnitude, highMagnitude);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 up = int256(units(LOG10_UP_PER_E, RELATIVE_BOUND, -52, true));
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 down = int256(units(LOG10_DOWN_PER_E, RELATIVE_BOUND, -52, true));
        return classify(low - down, high + up);
    }

    /// log10 |a| for a nonzero a other than +-1, from the oracle, as its sign
    /// and |log10 |a|| = whole + fraction 10^fractionExponent, both parts
    /// non-negative, the fraction between its outward rounded bounds.
    ///
    /// For a within 1e-3 of 1, log10 a = u ln(1 + u) / u / ln 10 for
    /// u = ±distance / unit. ln(1 + u) / u is within 50 units of 1e-70 and at
    /// least 0.9995, and ORACLE_LN10 is truncated by under a unit, so the
    /// quotient is within 6e-69 relative: `nearOne`. Any other a has the
    /// oracle's log10, within 1e-67.
    function log10Abs(int256 signedCoefficient, int256 exponent) internal pure returns (Log10 memory log) {
        uint256 magnitude = LibTestExactDecimal.abs(signedCoefficient);
        if (exponent < 0 && exponent >= -76) {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 unit = 10 ** uint256(-exponent);
            bool below = magnitude < unit;
            uint256 distance = below ? unit - magnitude : magnitude - unit;
            if (distance <= unit / 1000) {
                uint256 ratio = LibTranscendentalOracle.lnOnePlusOverRatio(distance, unit, below);
                // distance is below 1e73, so lifting it to [1e75, 1e76)
                // keeps the quotient's rounding under 3e-75 relative.
                uint256 lift = 0;
                while (distance < 1e75) {
                    distance *= 10;
                    lift++;
                }
                log.negative = below;
                log.nearOne = true;
                // forge-lint: disable-next-line(unsafe-typecast)
                log.fractionExponent = exponent - int256(lift);
                log.lowFraction = Math.mulDiv(distance, ratio, ORACLE_LN10 + 1, Math.Rounding.Floor);
                log.highFraction = Math.mulDiv(distance, ratio, ORACLE_LN10, Math.Rounding.Ceil);
                return log;
            }
        }
        (int256 characteristic, uint256 fraction) = LibTranscendentalOracle.log10(magnitude, exponent);
        log.fractionExponent = -70;
        if (characteristic >= 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            log.whole = uint256(characteristic);
        } else {
            // characteristic + fraction is
            // -((-characteristic - 1) + (1 - fraction)).
            log.negative = true;
            // forge-lint: disable-next-line(unsafe-typecast)
            log.whole = uint256(-characteristic);
            if (fraction > 0) {
                log.whole -= 1;
                fraction = ORACLE_ONE - fraction;
            }
        }
        log.lowFraction = fraction;
        log.highFraction = fraction;
    }

    /// Bounds on L = b log10 |a| in units, widened by the oracle's error:
    /// 1e-67 |b|, or for `nearOne` 6e-69 |L|, rounded up to 1e-68.
    function powLog(Float a, Float b) internal pure returns (int256, int256) {
        (int256 signedCoefficientA, int256 exponentA) = unpack(a);
        (int256 signedCoefficientB, int256 exponentB) = unpack(b);
        uint256 magnitudeB = LibTestExactDecimal.abs(signedCoefficientB);
        Log10 memory log = log10Abs(signedCoefficientA, exponentA);
        uint256 lowMagnitude = Math.min(
            units(magnitudeB, log.whole, exponentB, false)
                + units(magnitudeB, log.lowFraction, exponentB + log.fractionExponent, false),
            CAP
        );
        uint256 highMagnitude = Math.min(
            units(magnitudeB, log.whole, exponentB, true)
                + units(magnitudeB, log.highFraction, exponentB + log.fractionExponent, true),
            CAP
        );
        uint256 error = log.nearOne ? highMagnitude / 1e68 + 1 : units(magnitudeB, 1, exponentB - 67, true);
        (int256 low, int256 high) = signed((signedCoefficientB < 0) != log.negative, lowMagnitude, highMagnitude);
        // Each term is at most CAP, so the sums fit.
        // forge-lint: disable-next-line(unsafe-typecast)
        return (low - int256(error), high + int256(error));
    }

    /// Where pow(a, b) lands, for a nonzero a other than +-1 and a nonzero b.
    /// E is the README's 5.0000004e-41 + 3N 1e-75, with |b| for N. Past |b|
    /// 3e71, E may exceed 1e-3 and R has no lower bound.
    function powRange(Float a, Float b) internal pure returns (PowRange) {
        (int256 low, int256 high) = powLog(a, b);
        (int256 signedCoefficientB, int256 exponentB) = unpack(b);
        uint256 magnitudeB = LibTestExactDecimal.abs(signedCoefficientB);
        uint256 up = units(LOG10_UP_PER_E, RELATIVE_BOUND, -52, true)
            + units(LOG10_UP_PER_E * 3, magnitudeB, exponentB - 79, true);
        uint256 down = LibTestExactDecimal.cmpScaled(
                LibTestExactDecimal.u512(magnitudeB), exponentB, LibTestExactDecimal.u512(3), 71
            ) <= 0
            ? units(LOG10_DOWN_PER_E, RELATIVE_BOUND, -52, true)
                + units(LOG10_DOWN_PER_E * 3, magnitudeB, exponentB - 79, true)
            : CAP;
        // forge-lint: disable-next-line(unsafe-typecast)
        return classify(low - int256(down), high + int256(up));
    }

    function unpack(Float x) internal pure returns (int256 signedCoefficient, int256 exponent) {
        uint256 bits = uint256(Float.unwrap(x));
        // forge-lint: disable-next-line(unsafe-typecast)
        signedCoefficient = int224(uint224(bits));
        // forge-lint: disable-next-line(unsafe-typecast)
        exponent = int32(uint32(bits >> 224));
    }

    /// Whether a range allows a return.
    function mayReturn(PowRange range) internal pure returns (bool) {
        return range != PowRange.Over && range != PowRange.Under;
    }

    /// Whether a range allows the range error on the `over` side.
    function mayRevert(PowRange range, bool over) internal pure returns (bool) {
        if (range == PowRange.Unbounded) {
            return true;
        }
        return over
            ? range == PowRange.Over || range == PowRange.OverEdge
            : range == PowRange.Under || range == PowRange.UnderEdge;
    }

    /// The revert of pow or pow10 past the range on the `over` side: the
    /// call's input `x`, its coefficient and exponent read from its bits.
    function rangeError(bool over, Float x) internal pure returns (bytes memory) {
        (int256 signedCoefficient, int256 exponent) = unpack(x);
        return abi.encodeWithSelector(
            over ? ExponentOverflow.selector : ExponentUnderflow.selector, signedCoefficient, exponent
        );
    }
}
