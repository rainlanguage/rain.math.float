// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {
    LibDecimalFloatImplementation,
    LOG10_RAW_ERROR,
    POW10_RAW_ERROR,
    POW_GUARD
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

/// The proven error bound E of each transcendental function, and the
/// monotonicity it implies: for x < y, the results r have r(x) <= r(y) + 2E.
library LibTestErrorBound {
    using LibDecimalFloat for Float;

    /// Half a unit in the 41st significant digit of a nonzero result. A
    /// result one digit wider than its rounding only makes this larger.
    function halfUnit(Float result) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = result.unpack();
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.maximizeFull(signedCoefficient, exponent);
        return LibDecimalFloat.packLossless(5, exponent + (signedCoefficient / 1e76 == 0 ? int256(34) : int256(35)));
    }

    /// log10: half a unit plus `LOG10_RAW_ERROR` units of 1e-50, absolute.
    function log10(Float result) internal pure returns (Float) {
        // forge-lint: disable-next-line(unsafe-typecast)
        Float raw = LibDecimalFloat.packLossless(int256(LOG10_RAW_ERROR), -50);
        return result.isZero() ? raw : halfUnit(result).add(raw);
    }

    /// pow10, relative: half of `POW_GUARD` plus `POW10_RAW_ERROR`, over a
    /// power of at least 1e50 units.
    function pow10() internal pure returns (Float) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return LibDecimalFloat.packLossless(int256(POW_GUARD / 2 + POW10_RAW_ERROR), -50);
    }

    /// pow, relative, for the integer part N of |b| and
    /// d = max(|a|, 1/|a|) - 1: 5.0000004e-41 + N min(K1, K2 d), with K1
    /// 1.7273e-76 and K2 1.5e-38 for b > 0, and K1 1.1728e-75 and K2
    /// 3.4786e-38 for b < 0, as `LibDecimalFloat.pow` derives. d, its product
    /// and the sum each truncate toward zero, so this is at most the bound.
    /// Where K2 d is the lesser |a| is within 3.5e-38 of one, so |a| - 1 and
    /// 1 - |a| are exact.
    function pow(Float a, Float b) internal pure returns (Float) {
        Float base = LibDecimalFloat.packLossless(50000004, -48);
        Float n = b.abs().integer();
        if (n.isZero()) {
            return base;
        }
        (int256 k1, int256 k1Exponent, int256 k2, int256 k2Exponent) = (17273, -80, 15, -39);
        if (b.lt(LibDecimalFloat.FLOAT_ZERO)) {
            (k1, k1Exponent, k2, k2Exponent) = (11728, -79, 34786, -42);
        }
        (int256 magnitude, int256 exponent) = a.unpack();
        if (magnitude < 0) {
            magnitude = -magnitude;
        }
        // For a zero a, whose d has no bound, K1.
        (int256 d, int256 dExponent) = (k1, k1Exponent);
        if (magnitude != 0) {
            if (LibDecimalFloatImplementation.lt(magnitude, exponent, 1, 0)) {
                (d, dExponent) = LibDecimalFloatImplementation.sub(1, 0, magnitude, exponent);
                (d, dExponent) = LibDecimalFloatImplementation.div(d, dExponent, magnitude, exponent);
            } else {
                (d, dExponent) = LibDecimalFloatImplementation.sub(magnitude, exponent, 1, 0);
            }
            (d, dExponent) = LibDecimalFloatImplementation.mul(k2, k2Exponent, d, dExponent);
            (d, dExponent) = LibDecimalFloatImplementation.min(d, dExponent, k1, k1Exponent);
        }
        (int256 count, int256 countExponent) = n.unpack();
        (d, dExponent) = LibDecimalFloatImplementation.mul(d, dExponent, count, countExponent);
        (int256 baseCoefficient, int256 baseExponent) = base.unpack();
        (d, dExponent) = LibDecimalFloatImplementation.add(d, dExponent, baseCoefficient, baseExponent);
        (Float bound,) = LibDecimalFloat.packLossy(d, dExponent);
        return bound;
    }

    /// sqrt, relative: correctly rounded, so half a unit in the 41st digit of
    /// a root of at least 1e40 units.
    function sqrt() internal pure returns (Float) {
        return LibDecimalFloat.packLossless(5, -41);
    }

    /// For x < y, an absolute bound gives f(x) - f(y) <= E(x) + E(y).
    function monotoneAbsolute(Float low, Float high, Float lowError, Float highError) internal pure returns (bool) {
        return low.sub(high).lte(lowError.add(highError));
    }

    /// The int32 exponent floor's 1e-2147483648, which a relative bound adds
    /// absolute: a result below 1e-2147483608 sheds digits to lift its
    /// exponent to the floor. Relative to t = signedCoefficient 10^exponent,
    /// that is 1e-2147483648 / |t|, zero where it is below the smallest Float.
    function floor(int256 signedCoefficient, int256 exponent) internal pure returns (Float) {
        (signedCoefficient, exponent) =
            LibDecimalFloatImplementation.div(1, type(int32).min, signedCoefficient, exponent);
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
        return LibDecimalFloatImplementation.mul(errorCoefficient, errorExponent, signedCoefficient, exponent);
    }

    /// For x < y and results r within E f + u of the true f, r(x) - u over
    /// 1 + E(x) <= f(x) <= f(y) <= r(y) + u over 1 - E(y), so r(x) - r(y) <=
    /// E(y) r(x) + E(x) r(y) + 3u, which is 2E of the larger and the floor's u.
    function monotoneRelative(Float low, Float high, Float lowError, Float highError) internal pure returns (bool) {
        (int256 limitCoefficient, int256 limitExponent) = scaled(highError, low);
        (int256 signedCoefficient, int256 exponent) = scaled(lowError, high);
        (limitCoefficient, limitExponent) =
            LibDecimalFloatImplementation.add(limitCoefficient, limitExponent, signedCoefficient, exponent);
        (limitCoefficient, limitExponent) =
            LibDecimalFloatImplementation.add(limitCoefficient, limitExponent, 3, type(int32).min);
        (signedCoefficient, exponent) = low.sub(high).unpack();
        return LibDecimalFloatImplementation.lte(signedCoefficient, exponent, limitCoefficient, limitExponent);
    }
}
