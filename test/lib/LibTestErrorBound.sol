// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";
import {LibTranscendentalOracle, ORACLE_ONE} from "test/lib/LibTranscendentalOracle.sol";

/// @dev log10Unrounded's error, in units of 1e-54, from its steps:
/// `log10Reduce` leaves R within 16.7 units of C / 10^S, 1.67e-74 relative,
/// which moves the log by under 1e-74; `log10Ratio` is within 1.0043e-50
/// below and 1.3e-51 relative above a log under 1. So under 1.0044e-50.
uint256 constant LOG10_RAW_ERROR_E54 = 10044;

/// @dev pow10Unrounded's error, in units of 1e-52 of a power in [1e50, 1e51)
/// units of 1e-50, from its steps: `exp10Fixed` floors its 16 constants and
/// multiplies, its series and its last multiply, so it is under 30.471e-50
/// relative below 10^m; truncating x's fraction to 1e-50 moves 10^x by
/// under ln 10 1e-50, 2.3026e-50 relative. Over a power below 10, that is
/// under 304.71 + 23.03 = 327.74 units of 1e-50.
uint256 constant POW10_RAW_ERROR_E52 = 32774;

/// @dev Half a unit in the 41st digit of a power in [1e50, 1e51) units of
/// 1e-50, which has 51 digits, in units of 1e-52: 5e9 units of 1e-50.
uint256 constant POW10_HALF_UNIT_E52 = 5e11;

/// @dev pow's error before its integer part, relative, in units of 1e-52:
/// rounding at 41 digits, 5e-41 of the product, plus the leg's 10^(f L)
/// for a fraction f below 1, within pow10's 3.2774e-48 relative plus
/// ln 10 f times log10Unrounded's 1.0044e-50, under 2.3128e-50. That is
/// 5.0000003300528e-41, rounded up to 5.00000033006e-41. The integer part's
/// truncations are under 2N 1e-75 and its product with the leg 1e-75 more,
/// within the 3N 1e-75 `LibTestErrorBound.pow` adds from N 1. At N 0 that
/// 1e-75, and the half-power root's (2N + 1.6) 1e-75 below N 2, are within
/// the rounding up.
uint256 constant POW_RELATIVE_ERROR_E52 = 500000033006;

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
    /// `LOG10_RAW_ERROR_E54` units of 1e-54, absolute. The unit is the
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
        return sum(unitCoefficient, unitExponent, int256(LOG10_RAW_ERROR_E54), -54);
    }

    /// Two bound terms summed by `addPartsWide` and packed, both truncating
    /// towards zero, so a positive bound is never looser.
    function sum(int256 ca, int256 ea, int256 cb, int256 eb) private pure returns (Float) {
        (, ca, ea) = LibTestExactDecimal.addPartsWide(ca, ea, cb, eb);
        (Float bound,) = LibDecimalFloat.packLossy(ca, ea);
        return bound;
    }

    /// `sum` of two bound Floats.
    function plus(Float a, Float b) internal pure returns (Float) {
        (int256 ca, int256 ea) = a.unpack();
        (int256 cb, int256 eb) = b.unpack();
        return sum(ca, ea, cb, eb);
    }

    /// Two bound Floats multiplied by `mulPayload` and packed, both truncating.
    function times(Float a, Float b) internal pure returns (Float) {
        (int256 ca, int256 ea) = a.unpack();
        (int256 cb, int256 eb) = b.unpack();
        (ca, ea) = LibTestExactDecimal.mulPayload(ca, ea, cb, eb);
        (Float bound,) = LibDecimalFloat.packLossy(ca, ea);
        return bound;
    }

    /// `log10` of a positive Float input.
    function log10(Float a) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = a.unpack();
        return log10(signedCoefficient, exponent);
    }

    /// pow10, relative: `POW10_HALF_UNIT_E52` plus `POW10_RAW_ERROR_E52`, over
    /// a true power of at least 1e50 units.
    function pow10() internal pure returns (Float) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return LibDecimalFloat.packLossless(int256(POW10_HALF_UNIT_E52 + POW10_RAW_ERROR_E52), -52);
    }

    /// pow, relative, for the integer part N of |b|: `POW_RELATIVE_ERROR_E52`
    /// units of 1e-52 and 3 N 1e-75. Every multiply and the inverse
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
        (n, exponent) = LibTestExactDecimal.mulPayload(n, exponent, 3, -75);
        // forge-lint: disable-next-line(unsafe-typecast)
        return sum(int256(POW_RELATIVE_ERROR_E52), -52, n, exponent);
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
        (, int256 spreadCoefficient, int256 spreadExponent) = LibTestExactDecimal.addPartsWide(ca, ea, -cb, eb);
        (ca, ea) = lowError.unpack();
        (cb, eb) = highError.unpack();
        (, ca, ea) = LibTestExactDecimal.addPartsWide(ca, ea, cb, eb);
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
        return LibTestExactDecimal.mulPayload(errorCoefficient, errorExponent, signedCoefficient, exponent);
    }

    /// For x < y and results r within E f + u of the true f, r(x) - u over
    /// 1 + E(x) <= f(x) <= f(y) <= r(y) + u over 1 - E(y), so r(x) - r(y) <=
    /// E(y) r(x) + E(x) r(y) + 3u, which is 2E of the larger and the floor's u.
    function monotoneRelative(Float low, Float high, Float lowError, Float highError) internal pure returns (bool) {
        (int256 limitCoefficient, int256 limitExponent) = scaled(highError, low);
        (int256 signedCoefficient, int256 exponent) = scaled(lowError, high);
        (, limitCoefficient, limitExponent) =
            LibTestExactDecimal.addPartsWide(limitCoefficient, limitExponent, signedCoefficient, exponent);
        (, limitCoefficient, limitExponent) =
            LibTestExactDecimal.addPartsWide(limitCoefficient, limitExponent, 3, type(int32).min);
        (int256 lowCoefficient, int256 lowExponent) = low.unpack();
        (int256 highCoefficient, int256 highExponent) = high.unpack();
        (, signedCoefficient, exponent) =
            LibTestExactDecimal.addPartsWide(lowCoefficient, lowExponent, -highCoefficient, highExponent);
        return LibTestExactDecimal.cmpParts(signedCoefficient, exponent, limitCoefficient, limitExponent) <= 0;
    }
}
