// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

/// log10 and 10^x in 1e36 fixed point from series, independent of the log
/// tables, as the truth the table based functions are measured against.
library LibTestTranscendental {
    using LibDecimalFloat for Float;

    uint256 internal constant ONE = 1e36;
    /// ln 2 and ln 10 scaled by ONE, rounded, from `bc -l`.
    uint256 internal constant LN_TWO = 693147180559945309417232121458176568;
    uint256 internal constant LN_TEN = 2302585092994045684017991454684364208;

    /// 2 atanh((x - 1) / (x + 1)) = ln x, for x in [1, 2] scaled by ONE.
    function lnNearOne(uint256 x) internal pure returns (uint256) {
        uint256 z = (x - ONE) * ONE / (x + ONE);
        uint256 zz = z * z / ONE;
        uint256 term = z;
        uint256 sum = 0;
        for (uint256 k = 1; term > 0; k += 2) {
            sum += term / k;
            term = term * zz / ONE;
        }
        return 2 * sum;
    }

    /// log10(x / ONE) scaled by ONE, for x in [ONE, 2^256 / ONE).
    function log10Scaled(uint256 x) internal pure returns (uint256) {
        uint256 k = 0;
        while (2 ** (k + 1) * ONE <= x) {
            k++;
        }
        return (k * LN_TWO + lnNearOne(x / 2 ** k)) * ONE / LN_TEN;
    }

    /// 10^(f / ONE) scaled by ONE, for f in [0, ONE].
    function pow10Scaled(uint256 f) internal pure returns (uint256) {
        uint256 y = f * LN_TEN / ONE / 8;
        uint256 term = ONE;
        uint256 sum = ONE;
        for (uint256 k = 1; term > 0; k++) {
            term = term * y / ONE / k;
            sum += term;
        }
        for (uint256 i = 0; i < 3; i++) {
            sum = sum * sum / ONE;
        }
        return sum;
    }

    /// log10(a) for a > 0, to within 1e-35.
    function log10(Float a) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = a.unpack();
        require(signedCoefficient > 0, "log10 reference domain");
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 coefficient = uint256(signedCoefficient);
        uint256 digits = 0;
        while (10 ** digits <= coefficient) {
            digits++;
        }
        uint256 mantissa = digits <= 37 ? coefficient * 10 ** (37 - digits) : coefficient / 10 ** (digits - 37);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 characteristic = int256(digits) - 1 + exponent;
        // forge-lint: disable-next-line(unsafe-typecast)
        return LibDecimalFloat.packLossless(int256(log10Scaled(mantissa)) + characteristic * int256(ONE), -36);
    }

    /// 10^x, relative to within 1e-34, wherever 10^x packs.
    function pow10(Float x) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = x.unpack();
        int256 integer;
        uint256 fraction;
        if (exponent >= 0) {
            require(exponent <= 10, "pow10 reference domain");
            // forge-lint: disable-next-line(unsafe-typecast)
            integer = signedCoefficient * int256(10 ** uint256(exponent));
        } else if (exponent >= -76) {
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 unit = int256(10 ** uint256(-exponent));
            integer = signedCoefficient / unit;
            if (signedCoefficient % unit < 0) {
                integer -= 1;
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 remainder = uint256(signedCoefficient - integer * unit);
            fraction = exponent >= -36
                // forge-lint: disable-next-line(unsafe-typecast)
                ? remainder * 10 ** uint256(36 + exponent)
                // forge-lint: disable-next-line(unsafe-typecast)
                : remainder / 10 ** uint256(-36 - exponent);
        } else {
            // |x| < 1e-9 and 10^x is 1 + x ln 10 to within 1e-18.
            uint256 magnitude = signedCoefficient < 0
                // forge-lint: disable-next-line(unsafe-typecast)
                ? uint256(-signedCoefficient)
                // forge-lint: disable-next-line(unsafe-typecast)
                : uint256(signedCoefficient);
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 shift = uint256(-36 - exponent);
            fraction = shift > 76 ? 0 : magnitude / 10 ** shift;
            if (signedCoefficient < 0 && fraction > 0) {
                integer = -1;
                fraction = ONE - fraction;
            }
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return LibDecimalFloat.packLossless(int256(pow10Scaled(fraction)), integer - 36);
    }

    /// a^b = 10^(b log10 a) for a > 0.
    function pow(Float a, Float b) internal pure returns (Float) {
        return pow10(b.mul(log10(a)));
    }

    function relativeError(Float actual, Float expected) internal pure returns (Float) {
        return actual.div(expected).sub(LibDecimalFloat.FLOAT_ONE).abs();
    }

    function absoluteError(Float actual, Float expected) internal pure returns (Float) {
        return actual.sub(expected).abs();
    }
}
