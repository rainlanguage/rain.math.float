// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";
import {LibTranscendentalOracle, ORACLE_LN10} from "test/lib/LibTranscendentalOracle.sol";

/// Where a power 10^L, computed within a slack of L in log10, can land against the
/// Float range. Only `Inside` demands a value; `Over` and `Under` demand the
/// matching revert; at an edge either is within the slack.
enum PowRange {
    Inside,
    Over,
    Under,
    OverEdge,
    UnderEdge
}

/// @dev log10 of the largest Float, int224.max 10^int32.max, truncated, from `bc -l`
/// at scale 60.
int256 constant LOG10_MAX_COEFFICIENT = 2147483714129689033067806532663773523561944969;
int256 constant LOG10_MAX_EXPONENT = -36;

library LibTestPowRange {
    /// Compares ca 10^ea with cb 10^eb exactly, returning -1, 0 or 1.
    function cmp(int256 ca, int256 ea, int256 cb, int256 eb) internal pure returns (int256) {
        int256 signA = ca > 0 ? int256(1) : ca < 0 ? int256(-1) : int256(0);
        int256 signB = cb > 0 ? int256(1) : cb < 0 ? int256(-1) : int256(0);
        if (signA != signB || signA == 0) {
            return signA < signB ? int256(-1) : signA > signB ? int256(1) : int256(0);
        }
        int256 magnitude = LibTestExactDecimal.cmpScaled(
            LibTestExactDecimal.u512(LibTestExactDecimal.abs(ca)),
            ea,
            LibTestExactDecimal.u512(LibTestExactDecimal.abs(cb)),
            eb
        );
        return signA * magnitude;
    }

    /// log10 |a| for a nonzero a other than +-1, unpacked, from the oracle.
    /// Within 1e-63 relative: a within 1e-3 of 1 goes through ln(1 + u) / u,
    /// relative to 1e-68, and any other has |log10 a| over 4.3e-4 against the
    /// oracle's 1e-67 absolute.
    function log10Abs(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 magnitude = uint256(signedCoefficient < 0 ? -signedCoefficient : signedCoefficient);
        if (exponent < 0 && exponent >= -76) {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 unit = 10 ** uint256(-exponent);
            bool below = magnitude < unit;
            uint256 distance = below ? unit - magnitude : magnitude - unit;
            if (distance <= unit / 1000) {
                uint256 ratio = LibTranscendentalOracle.lnOnePlusOverRatio(distance, unit, below);
                // distance is under 1e74 and ratio under 2e70, so both fit.
                // forge-lint: disable-next-line(unsafe-typecast)
                (int256 c, int256 e) = LibTestExactDecimal.mulParts(int256(distance), exponent, int256(ratio), -70);
                // forge-lint: disable-next-line(unsafe-typecast)
                (c, e) = LibTestExactDecimal.divParts(c, e, int256(ORACLE_LN10), -70);
                return (below ? -c : c, e);
            }
        }
        (int256 characteristic, uint256 fraction) = LibTranscendentalOracle.log10(magnitude, exponent);
        // fraction is under 1e70 and so fits.
        // forge-lint: disable-next-line(unsafe-typecast)
        return LibTestExactDecimal.addParts(characteristic, 0, int256(fraction), -70);
    }

    /// The range of a power 10^L for L = signedCoefficient 10^exponent, where
    /// the computed power is within `slackCoefficient` 10^`slackExponent` of L
    /// in log10. L itself is taken as within 1e-60 relative plus 1e-30
    /// absolute.
    function range(int256 signedCoefficient, int256 exponent, int256 slackCoefficient, int256 slackExponent)
        internal
        pure
        returns (PowRange)
    {
        (int256 marginCoefficient, int256 marginExponent) =
            (signedCoefficient < 0 ? -signedCoefficient : signedCoefficient, exponent - 60);
        (marginCoefficient, marginExponent) = LibTestExactDecimal.addParts(marginCoefficient, marginExponent, 1, -30);
        (marginCoefficient, marginExponent) =
            LibTestExactDecimal.addParts(marginCoefficient, marginExponent, slackCoefficient, slackExponent);

        (int256 highCoefficient, int256 highExponent) =
            LibTestExactDecimal.addParts(signedCoefficient, exponent, marginCoefficient, marginExponent);
        (int256 lowCoefficient, int256 lowExponent) =
            LibTestExactDecimal.addParts(signedCoefficient, exponent, -marginCoefficient, marginExponent);

        if (cmp(lowCoefficient, lowExponent, LOG10_MAX_COEFFICIENT, LOG10_MAX_EXPONENT) > 0) {
            return PowRange.Over;
        } else if (cmp(highCoefficient, highExponent, type(int32).min, 0) < 0) {
            return PowRange.Under;
        } else if (
            !(cmp(highCoefficient, highExponent, LOG10_MAX_COEFFICIENT, LOG10_MAX_EXPONENT) > 0)
                && !(cmp(lowCoefficient, lowExponent, type(int32).min, 0) < 0)
        ) {
            return PowRange.Inside;
        }
        return signedCoefficient > 0 ? PowRange.OverEdge : PowRange.UnderEdge;
    }
}
