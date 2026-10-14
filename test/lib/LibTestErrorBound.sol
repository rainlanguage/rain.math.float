// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float} from "src/lib/LibDecimalFloat.sol";
import {LibExactFloat, ORACLE_ONE} from "test/lib/LibExactFloat.sol";

/// @dev log10Unrounded's error, in units of 1e-54, from its steps:
/// `log10Reduce` leaves R within 16.7 units of C / 10^S, 1.67e-74 relative,
/// which moves the log by under 1e-74; `log10Ratio` is within
/// 1 + 0.8686 8.0226 z units of 1e-50 below, for z at most 5.1e-4, under
/// 1.0036e-50, and 1.3e-51 relative above a log under 1. So under
/// 1.0037e-50.
uint256 constant LOG10_RAW_ERROR_E54 = 10037;

/// @dev pow10Unrounded's error, in units of 1e-52 of a power in [1e50, 1e51)
/// units of 1e-50, from its steps. For m = k 2^-16 + r, r below 2^-16,
/// `exp10Fixed`'s steps give P, E_k = 10^(k 2^-16) 1e50 - P below the power
/// at r = 0; its floored series is under 1.07902 units below 10^r 1e50 and
/// its last multiply under a unit, so it is under E_k 10^r + 1.07902 P / 1e50
/// + 1 below 10^m 1e50. Truncating x's fraction to 1e-50 moves 10^x by under
/// ln 10 10^m units. Over every k (crates/tests `fixed.rs` enumerates them)
/// that is at most 111.1006 units of 1e-50, at k = 2^16 - 1.
uint256 constant POW10_RAW_ERROR_E52 = 11111;

/// @dev Half a unit in the 41st digit of a power in [1e50, 1e51) units of
/// 1e-50, which has 51 digits, in units of 1e-52: 5e9 units of 1e-50.
uint256 constant POW10_HALF_UNIT_E52 = 5e11;

/// @dev pow's error before its integer part, relative, in units of 1e-52:
/// rounding at 41 digits, 5e-41 of the product, plus the leg's 10^(f L)
/// for a fraction f below 1, within pow10's 1.1111e-48 relative plus
/// ln 10 f times log10Unrounded's 1.0037e-50, under 2.3112e-50. That is
/// 5.0000001134212e-41, rounded up to 5.00000011343e-41. The integer part's
/// truncations are within the N min(K1, K2 d) `LibTestErrorBound.pow` adds.
/// The rest `LibDecimalFloat.pow` derives, the 1/2 per bit, the leg's
/// product, the inverse's weight in the leg, the half-power root's extra
/// square, multiply and dropped digit, and the higher orders, is under
/// 1e-63, within the rounding up's 8.8e-53.
uint256 constant POW_RELATIVE_ERROR_E52 = 500000011343;

/// @dev K1 of pow for b > 0, in units of 1e-80: a multiply truncates toward
/// zero to a coefficient of at least 2^255 / 10, so it drops under
/// 10 / 2^255 relative, 17272.3 units, and the squarings and multiplies
/// weigh it under N.
uint256 constant POW_K1_E80 = 17273;

/// @dev K1 of pow for b < 0, in units of 1e-80: `POW_K1_E80` plus the
/// inverse's under 1e-75 relative, as it truncates to a coefficient of at
/// least 1e75, which a^-N weighs N. 117273 units, rounded up to 117280.
uint256 constant POW_INVERSE_K1_E80 = 117280;

/// @dev K2 of pow for b > 0, in units of 1e-42: squaring a^(2^j) and its
/// multiply drop under min(4^j d^2, 1e-76) weighed N / 2^(j+1), which with
/// s = 2^j d / 1e-38 is (N d 1e-38 / 2) min(s, 1/s); s doubles in j, so they
/// sum under 3 of it, 1.5e-38 N d.
uint256 constant POW_K2_E42 = 15000;

/// @dev K2 of pow for b < 0, in units of 1e-42: below d 1e-38 the squarings
/// and the inverse's d^2 N drop under 2.5e-38 N d. Above it the squarings
/// drop under 1e-76 N and the inverse min(d^2, 1e-75) N, over N d most at
/// d = sqrt(1e-75): 1.1e-75 / sqrt(1e-75), 34785.05 units, rounded up.
uint256 constant POW_INVERSE_K2_E42 = 34786;

/// The proven error bound E of each transcendental function, and the
/// monotonicity it implies: for x < y, the results r have r(x) <= r(y) + 2E.
/// Every bound is packed and unpacked from its bits by `LibExactFloat`, never
/// by the library under test (#672).
library LibTestErrorBound {
    /// The Float toward zero of `signedCoefficient × 10^exponent`, from its
    /// bits.
    function pack(int256 signedCoefficient, int256 exponent) private pure returns (Float) {
        return Float.wrap(LibExactFloat.packTowardZero(signedCoefficient, exponent));
    }

    /// A Float's parts, from its bits.
    function unpack(Float x) private pure returns (int256, int256) {
        return LibExactFloat.unpackBits(Float.unwrap(x));
    }

    /// Half a unit in the 41st significant digit of magnitude 10^exponent,
    /// zero for a zero magnitude.
    function halfUnit(uint256 magnitude, int256 exponent) internal pure returns (Float) {
        if (magnitude == 0) {
            return Float.wrap(0);
        }
        int256 order = exponent - 1;
        for (; magnitude > 0; magnitude /= 10) {
            order++;
        }
        return pack(5, order - 41);
    }

    /// log10 of a positive input: half a unit of the true log plus
    /// `LOG10_RAW_ERROR_E54` units of 1e-54, absolute. The unit is the
    /// oracle's less its 1e-67, the smaller one where that straddles a power
    /// of ten, as a raw log past the power rounds to it or is far inside the
    /// raw error of it.
    function log10(int256 signedCoefficient, int256 exponent) internal pure returns (Float) {
        // The input is positive.
        // forge-lint: disable-next-line(unsafe-typecast)
        (int256 characteristic, uint256 fraction) = LibExactFloat.log10(uint256(signedCoefficient), exponent);
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
        (int256 unitCoefficient, int256 unitExponent) = unpack(whole > 0 ? halfUnit(whole, 0) : halfUnit(fraction, -70));
        // forge-lint: disable-next-line(unsafe-typecast)
        return sum(unitCoefficient, unitExponent, int256(LOG10_RAW_ERROR_E54), -54);
    }

    /// Two bound terms summed by `addPartsWide` and packed by `pack`, both
    /// truncating towards zero, so a positive bound is never looser.
    function sum(int256 ca, int256 ea, int256 cb, int256 eb) private pure returns (Float) {
        (, ca, ea) = LibExactFloat.addPartsWide(ca, ea, cb, eb);
        return pack(ca, ea);
    }

    /// `sum` of two bound Floats.
    function plus(Float a, Float b) internal pure returns (Float) {
        (int256 ca, int256 ea) = unpack(a);
        (int256 cb, int256 eb) = unpack(b);
        return sum(ca, ea, cb, eb);
    }

    /// Two bound Floats multiplied by `mulPayload` and packed, both truncating.
    function times(Float a, Float b) internal pure returns (Float) {
        (int256 ca, int256 ea) = unpack(a);
        (int256 cb, int256 eb) = unpack(b);
        (ca, ea) = LibExactFloat.mulPayload(ca, ea, cb, eb);
        return pack(ca, ea);
    }

    /// `log10` of a positive Float input.
    function log10(Float a) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = unpack(a);
        return log10(signedCoefficient, exponent);
    }

    /// pow10, relative: `POW10_HALF_UNIT_E52` plus `POW10_RAW_ERROR_E52`, over
    /// a true power of at least 1e50 units.
    function pow10() internal pure returns (Float) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return pack(int256(POW10_HALF_UNIT_E52 + POW10_RAW_ERROR_E52), -52);
    }

    /// pow, relative, for the integer part N of |b| and
    /// d = max(|a|, 1/|a|) - 1: `POW_RELATIVE_ERROR_E52` units of 1e-52 plus
    /// N min(K1, K2 d), with `POW_K1_E80` and `POW_K2_E42` for b > 0 and
    /// `POW_INVERSE_K1_E80` and `POW_INVERSE_K2_E42` for b < 0. Where K2 d
    /// is the lesser |a| is within 3.5e-38 of one, so |a| - 1 and 1 - |a| are
    /// exact; the quotient, the products and the sum each truncate toward
    /// zero, so this is at most the bound. A zero a, whose d has no bound,
    /// takes K1.
    function pow(Float a, Float b) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = unpack(b);
        // A Float coefficient is int224, so its magnitude fits int256.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 n = int256(LibExactFloat.abs(signedCoefficient));
        if (exponent < 0) {
            (n, exponent) = (LibExactFloat.atExponent(n, exponent, 0), 0);
        }
        (uint256 k1, uint256 k2) =
            signedCoefficient < 0 ? (POW_INVERSE_K1_E80, POW_INVERSE_K2_E42) : (POW_K1_E80, POW_K2_E42);
        // forge-lint: disable-next-line(unsafe-typecast)
        (int256 perUnit, int256 perUnitExponent) = (int256(k1), int256(-80));
        (int256 magnitude, int256 magnitudeExponent) = unpack(a);
        // A Float coefficient is int224, so its magnitude fits int256.
        // forge-lint: disable-next-line(unsafe-typecast)
        magnitude = int256(LibExactFloat.abs(magnitude));
        if (magnitude != 0) {
            int256 d;
            int256 dExponent;
            if (LibExactFloat.cmpParts(magnitude, magnitudeExponent, 1, 0) < 0) {
                (, d, dExponent) = LibExactFloat.addPartsWide(1, 0, -magnitude, magnitudeExponent);
                (d, dExponent) = LibExactFloat.quotient(d, dExponent, magnitude, magnitudeExponent);
            } else {
                (, d, dExponent) = LibExactFloat.addPartsWide(magnitude, magnitudeExponent, -1, 0);
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            (d, dExponent) = LibExactFloat.mulPayload(int256(k2), -42, d, dExponent);
            if (LibExactFloat.cmpParts(d, dExponent, perUnit, perUnitExponent) < 0) {
                (perUnit, perUnitExponent) = (d, dExponent);
            }
        }
        (n, exponent) = LibExactFloat.mulPayload(perUnit, perUnitExponent, n, exponent);
        // forge-lint: disable-next-line(unsafe-typecast)
        return sum(int256(POW_RELATIVE_ERROR_E52), -52, n, exponent);
    }

    /// sqrt, relative: correctly rounded, so half a unit in the 41st digit of
    /// a root of at least 1e40 units.
    function sqrt() internal pure returns (Float) {
        return pack(5, -41);
    }

    /// For x < y, an absolute bound gives f(x) - f(y) <= E(x) + E(y).
    function monotoneAbsolute(Float low, Float high, Float lowError, Float highError) internal pure returns (bool) {
        (int256 ca, int256 ea) = unpack(low);
        (int256 cb, int256 eb) = unpack(high);
        (, int256 spreadCoefficient, int256 spreadExponent) = LibExactFloat.addPartsWideUp(ca, ea, -cb, eb);
        (ca, ea) = unpack(lowError);
        (cb, eb) = unpack(highError);
        (, ca, ea) = LibExactFloat.addPartsWide(ca, ea, cb, eb);
        return LibExactFloat.cmpParts(spreadCoefficient, spreadExponent, ca, ea) <= 0;
    }

    /// The int32 exponent floor's 1e-2147483648, which a relative bound adds
    /// absolute: a result below 1e-2147483608 sheds digits to lift its
    /// exponent to the floor. Relative to t = signedCoefficient 10^exponent,
    /// that is 1e-2147483648 / |t|, zero where it is below the smallest Float.
    function floor(int256 signedCoefficient, int256 exponent) internal pure returns (Float) {
        (signedCoefficient, exponent) = LibExactFloat.quotient(1, type(int32).min, signedCoefficient, exponent);
        // The quotient's coefficient is at most 77 digits, so its magnitude
        // fits int256.
        // forge-lint: disable-next-line(unsafe-typecast)
        return pack(int256(LibExactFloat.abs(signedCoefficient)), exponent);
    }

    /// `floor` relative to a nonzero Float.
    function floor(Float x) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = unpack(x);
        return floor(signedCoefficient, exponent);
    }

    /// E |x|, unpacked, as it underflows a Float near the floor.
    function scaled(Float error, Float x) private pure returns (int256, int256) {
        (int256 errorCoefficient, int256 errorExponent) = unpack(error);
        (int256 signedCoefficient, int256 exponent) = unpack(x);
        // A Float coefficient is int224, so its magnitude fits int256.
        // forge-lint: disable-next-line(unsafe-typecast)
        signedCoefficient = int256(LibExactFloat.abs(signedCoefficient));
        return LibExactFloat.mulPayload(errorCoefficient, errorExponent, signedCoefficient, exponent);
    }

    /// For x < y and results r within E f + u of the true f, r(x) - u over
    /// 1 + E(x) <= f(x) <= f(y) <= r(y) + u over 1 - E(y), so r(x) - r(y) <=
    /// E(y) r(x) + E(x) r(y) + 3u, which is 2E of the larger and the floor's u.
    function monotoneRelative(Float low, Float high, Float lowError, Float highError) internal pure returns (bool) {
        (int256 limitCoefficient, int256 limitExponent) = scaled(highError, low);
        (int256 signedCoefficient, int256 exponent) = scaled(lowError, high);
        (, limitCoefficient, limitExponent) =
            LibExactFloat.addPartsWide(limitCoefficient, limitExponent, signedCoefficient, exponent);
        (, limitCoefficient, limitExponent) =
            LibExactFloat.addPartsWide(limitCoefficient, limitExponent, 3, type(int32).min);
        (int256 lowCoefficient, int256 lowExponent) = unpack(low);
        (int256 highCoefficient, int256 highExponent) = unpack(high);
        (, signedCoefficient, exponent) =
            LibExactFloat.addPartsWideUp(lowCoefficient, lowExponent, -highCoefficient, highExponent);
        return LibExactFloat.cmpParts(signedCoefficient, exponent, limitCoefficient, limitExponent) <= 0;
    }
}
