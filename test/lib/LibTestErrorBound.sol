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

    /// pow, relative, for the integer part N of |b|: 5.00006e-41, pow10's
    /// bound plus log10Unrounded's 2.245e-47 times a fraction below 1 and
    /// ln 10, plus the packing, and 3 N 1e-75. Every multiply and the inverse
    /// truncate toward zero by under 1e-75, and squaring to the Nth power
    /// weights them by at most 2N in all, so the integer part is within
    /// 1 - (1 - 1e-75)^(2N), under 2N 1e-75; its product with the leg is
    /// under N 1e-75.
    function pow(Float b) internal pure returns (Float) {
        return
            LibDecimalFloat.packLossless(500006, -46).add(b.abs().integer().mul(LibDecimalFloat.packLossless(3, -75)));
    }

    /// For x < y, an absolute bound gives f(x) - f(y) <= E(x) + E(y).
    function monotoneAbsolute(Float low, Float high, Float lowError, Float highError) internal pure returns (bool) {
        return low.sub(high).lte(lowError.add(highError));
    }

    /// For x < y and results r, relative bounds give r(x) / (1 + E(x)) <=
    /// f(x) <= f(y) <= r(y) / (1 - E(y)), so r(x) - r(y) <= E(y) r(x) +
    /// E(x) r(y), which is 2E of the larger.
    function monotoneRelative(Float low, Float high, Float lowError, Float highError) internal pure returns (bool) {
        return low.sub(high).lte(highError.mul(low.abs()).add(lowError.mul(high.abs())));
    }
}
