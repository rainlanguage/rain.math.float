// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";
import {LibTranscendentalOracle, ORACLE_ONE} from "test/lib/LibTranscendentalOracle.sol";

/// @dev log10's raw error in units of 1e-50: the README's 2e-50.
uint256 constant DOCUMENTED_LOG10_RAW_ERROR = 2;

/// @dev pow10's raw error in units of 1e-50: the README's 3.28e-8 of a unit
/// of `DOCUMENTED_POW_GUARD`.
uint256 constant DOCUMENTED_POW10_RAW_ERROR = 328;

/// @dev Units of 1e-50 in a unit of the 41st digit of a power of 1e50 to 1e51
/// units.
uint256 constant DOCUMENTED_POW_GUARD = 1e10;

/// The proven error bound E of each transcendental function, and the
/// monotonicity it implies: for x < y, the results r have r(x) <= r(y) + 2E.
library LibTestErrorBound {
    using LibDecimalFloat for Float;

    /// Half a unit in the 41st significant digit of magnitude 10^exponent,
    /// zero for a zero magnitude.
    function halfUnit(uint256 magnitude, int256 exponent) internal pure returns (Float) {
        if (magnitude == 0) {
            return LibDecimalFloat.FLOAT_ZERO;
        }
        int256 order = exponent - 1;
        for (; magnitude > 0; magnitude /= 10) {
            order++;
        }
        return LibDecimalFloat.packLossless(5, order - 41);
    }

    /// log10 of a positive input: half a unit of the true log plus
    /// `DOCUMENTED_LOG10_RAW_ERROR` units of 1e-50, absolute. The unit is the
    /// oracle's less its 1e-67, the smaller one where that straddles a power
    /// of ten, as a raw log past the power rounds to it or is far inside the
    /// raw error of it.
    function log10(int256 signedCoefficient, int256 exponent) internal pure returns (Float) {
        // The input is positive.
        // forge-lint: disable-next-line(unsafe-typecast)
        (int256 characteristic, uint256 fraction) = LibTranscendentalOracle.log10(uint256(signedCoefficient), exponent);
        // |log10| as whole + fraction / ORACLE_ONE.
        uint256 whole;
        if (characteristic >= 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            whole = uint256(characteristic);
        } else if (fraction == 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            whole = uint256(-characteristic);
        } else {
            // forge-lint: disable-next-line(unsafe-typecast)
            whole = uint256(-characteristic) - 1;
            fraction = ORACLE_ONE - fraction;
        }
        // Less the oracle's 1e-67, 1000 units of 1e-70.
        if (fraction >= 1000) {
            fraction -= 1000;
        } else if (whole > 0) {
            whole -= 1;
            fraction += ORACLE_ONE - 1000;
        } else {
            fraction = 0;
        }
        (int256 unitCoefficient, int256 unitExponent) =
            (whole > 0 ? halfUnit(whole, 0) : halfUnit(fraction, -70)).unpack();
        // forge-lint: disable-next-line(unsafe-typecast)
        return sum(unitCoefficient, unitExponent, int256(DOCUMENTED_LOG10_RAW_ERROR), -50);
    }

    /// Two bound terms summed by `sumParts` and packed, both truncating
    /// towards zero, so a positive bound is never looser.
    function sum(int256 ca, int256 ea, int256 cb, int256 eb) private pure returns (Float) {
        (ca, ea) = LibTestExactDecimal.sumParts(ca, ea, cb, eb);
        (Float bound,) = LibDecimalFloat.packLossy(ca, ea);
        return bound;
    }

    /// `sum` of two bound Floats.
    function plus(Float a, Float b) internal pure returns (Float) {
        (int256 ca, int256 ea) = a.unpack();
        (int256 cb, int256 eb) = b.unpack();
        return sum(ca, ea, cb, eb);
    }

    /// Two bound Floats multiplied by `mulParts` and packed, both truncating.
    function times(Float a, Float b) internal pure returns (Float) {
        (int256 ca, int256 ea) = a.unpack();
        (int256 cb, int256 eb) = b.unpack();
        (ca, ea) = LibTestExactDecimal.mulParts(ca, ea, cb, eb);
        (Float bound,) = LibDecimalFloat.packLossy(ca, ea);
        return bound;
    }

    /// `log10` of a positive Float input.
    function log10(Float a) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = a.unpack();
        return log10(signedCoefficient, exponent);
    }

    /// pow10, relative: half of `DOCUMENTED_POW_GUARD` plus
    /// `DOCUMENTED_POW10_RAW_ERROR`, over a power of at least 1e50 units.
    function pow10() internal pure returns (Float) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return LibDecimalFloat.packLossless(int256(DOCUMENTED_POW_GUARD / 2 + DOCUMENTED_POW10_RAW_ERROR), -50);
    }

    /// pow, relative, for the integer part N of |b|: 5.0000004e-41, pow10's
    /// bound plus log10Unrounded's 2e-50 times a fraction below 1 and
    /// ln 10, plus the packing, and 3 N 1e-75. Every multiply and the inverse
    /// truncate toward zero by under 1e-75, and squaring to the Nth power
    /// weights them by at most 2N in all, so the integer part is within
    /// 1 - (1 - 1e-75)^(2N), under 2N 1e-75; its product with the leg is
    /// under N 1e-75.
    function pow(Float b) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = b.unpack();
        // A Float coefficient is int224, so its magnitude fits int256.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 n = int256(LibTestExactDecimal.abs(signedCoefficient));
        if (exponent < 0) {
            (n, exponent) = (LibTestExactDecimal.atExponent(n, exponent, 0), 0);
        }
        (n, exponent) = LibTestExactDecimal.mulParts(n, exponent, 3, -75);
        return sum(50000004, -48, n, exponent);
    }

    /// sqrt, relative: correctly rounded, so half a unit in the 41st digit of
    /// a root of at least 1e40 units.
    function sqrt() internal pure returns (Float) {
        return LibDecimalFloat.packLossless(5, -41);
    }

    /// For x < y, an absolute bound gives f(x) - f(y) <= E(x) + E(y).
    function monotoneAbsolute(Float low, Float high, Float lowError, Float highError) internal pure returns (bool) {
        (int256 ca, int256 ea) = low.unpack();
        (int256 cb, int256 eb) = high.unpack();
        (int256 spreadCoefficient, int256 spreadExponent) = LibTestExactDecimal.sumParts(ca, ea, -cb, eb);
        (ca, ea) = lowError.unpack();
        (cb, eb) = highError.unpack();
        (ca, ea) = LibTestExactDecimal.sumParts(ca, ea, cb, eb);
        return LibTestExactDecimal.cmpParts(spreadCoefficient, spreadExponent, ca, ea) <= 0;
    }

    /// The int32 exponent floor's 1e-2147483648, which a relative bound adds
    /// absolute: a result below 1e-2147483608 sheds digits to lift its
    /// exponent to the floor. Relative to t = signedCoefficient 10^exponent,
    /// that is 1e-2147483648 / |t|, zero where it is below the smallest Float.
    function floor(int256 signedCoefficient, int256 exponent) internal pure returns (Float) {
        (signedCoefficient, exponent) = LibTestExactDecimal.quotient(1, type(int32).min, signedCoefficient, exponent);
        (Float relative,) = LibDecimalFloat.packLossy(signedCoefficient, exponent);
        return relative.abs();
    }

    /// `floor` relative to a nonzero Float.
    function floor(Float x) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = x.unpack();
        return floor(signedCoefficient, exponent);
    }

    /// E |x|, unpacked, as it underflows a Float near the floor.
    function scaled(Float error, Float x) private pure returns (int256, int256) {
        (int256 errorCoefficient, int256 errorExponent) = error.unpack();
        (int256 signedCoefficient, int256 exponent) = x.abs().unpack();
        return LibTestExactDecimal.mulParts(errorCoefficient, errorExponent, signedCoefficient, exponent);
    }

    /// For x < y and results r within E f + u of the true f, r(x) - u over
    /// 1 + E(x) <= f(x) <= f(y) <= r(y) + u over 1 - E(y), so r(x) - r(y) <=
    /// E(y) r(x) + E(x) r(y) + 3u, which is 2E of the larger and the floor's u.
    function monotoneRelative(Float low, Float high, Float lowError, Float highError) internal pure returns (bool) {
        (int256 limitCoefficient, int256 limitExponent) = scaled(highError, low);
        (int256 signedCoefficient, int256 exponent) = scaled(lowError, high);
        (limitCoefficient, limitExponent) =
            LibTestExactDecimal.sumParts(limitCoefficient, limitExponent, signedCoefficient, exponent);
        (limitCoefficient, limitExponent) =
            LibTestExactDecimal.sumParts(limitCoefficient, limitExponent, 3, type(int32).min);
        (int256 lowCoefficient, int256 lowExponent) = low.unpack();
        (int256 highCoefficient, int256 highExponent) = high.unpack();
        (signedCoefficient, exponent) =
            LibTestExactDecimal.sumParts(lowCoefficient, lowExponent, -highCoefficient, highExponent);
        return LibTestExactDecimal.cmpParts(signedCoefficient, exponent, limitCoefficient, limitExponent) <= 0;
    }
}
