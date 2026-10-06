// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
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
            if (distance * 1000 <= unit) {
                uint256 ratio = LibTranscendentalOracle.lnOnePlusOverRatio(distance, unit, below);
                // distance is under 1e74 and ratio under 2e70, so both fit.
                // forge-lint: disable-next-line(unsafe-typecast)
                (int256 c, int256 e) = LibDecimalFloatImplementation.mul(int256(distance), exponent, int256(ratio), -70);
                // forge-lint: disable-next-line(unsafe-typecast)
                (c, e) = LibDecimalFloatImplementation.div(c, e, int256(ORACLE_LN10), -70);
                return (below ? -c : c, e);
            }
        }
        (int256 characteristic, uint256 fraction) = LibTranscendentalOracle.log10(magnitude, exponent);
        // fraction is under 1e70 and so fits.
        // forge-lint: disable-next-line(unsafe-typecast)
        return LibDecimalFloatImplementation.add(characteristic, 0, int256(fraction), -70);
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
        (int256 marginCoefficient, int256 marginExponent) = LibDecimalFloatImplementation.mul(
            signedCoefficient < 0 ? -signedCoefficient : signedCoefficient, exponent, 1, -60
        );
        (marginCoefficient, marginExponent) =
            LibDecimalFloatImplementation.add(marginCoefficient, marginExponent, 1, -30);
        (marginCoefficient, marginExponent) =
            LibDecimalFloatImplementation.add(marginCoefficient, marginExponent, slackCoefficient, slackExponent);

        (int256 highCoefficient, int256 highExponent) =
            LibDecimalFloatImplementation.add(signedCoefficient, exponent, marginCoefficient, marginExponent);
        (int256 lowCoefficient, int256 lowExponent) =
            LibDecimalFloatImplementation.sub(signedCoefficient, exponent, marginCoefficient, marginExponent);

        if (LibDecimalFloatImplementation.gt(lowCoefficient, lowExponent, LOG10_MAX_COEFFICIENT, LOG10_MAX_EXPONENT)) {
            return PowRange.Over;
        } else if (LibDecimalFloatImplementation.lt(highCoefficient, highExponent, type(int32).min, 0)) {
            return PowRange.Under;
        } else if (
            !LibDecimalFloatImplementation.gt(highCoefficient, highExponent, LOG10_MAX_COEFFICIENT, LOG10_MAX_EXPONENT)
                && !LibDecimalFloatImplementation.lt(lowCoefficient, lowExponent, type(int32).min, 0)
        ) {
            return PowRange.Inside;
        }
        return signedCoefficient > 0 ? PowRange.OverEdge : PowRange.UnderEdge;
    }
}
