// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    LibDecimalFloatImplementation,
    POW_FIXED_ONE,
    POW_FIXED_LN10
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Log10RatioRelativeSumTooSmall} from "src/error/ErrDecimalFloat.sol";

/// `log10Ratio` verbatim from
/// `src/lib/implementation/LibDecimalFloatImplementation.sol` at 5210e11,
/// the #336 head, before the relative path scaled by a cascade. The helpers
/// it calls are called on the live library. Equivalence tests only.
library LibDecimalFloatImplementationLog10RatioPr336 {
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
            // difference is below 1e76 so it fits and maximizes in place.
            // forge-lint: disable-next-item(unsafe-typecast)
            (int256 differenceCoefficient, int256 differenceExponent) =
                LibDecimalFloatImplementation.maximizeFull(int256(difference), 0);
            // forge-lint: disable-next-line(unsafe-typecast)
            difference = uint256(differenceCoefficient);
            exponent += differenceExponent;
        } else {
            z = LibDecimalFloatImplementation.mulDiv(difference, POW_FIXED_ONE, sum);
        }
        uint256 zSquared = LibDecimalFloatImplementation.mulDivFixed(z, z);
        // atanh(z) / z
        uint256 series = POW_FIXED_ONE;
        uint256 term = POW_FIXED_ONE;
        for (uint256 k = 3; term > 0; k += 2) {
            term = LibDecimalFloatImplementation.mulDivFixed(term, zSquared);
            series += term / k;
        }
        // The scaled series is below 0.8686e50, so the quotient is below it
        // when not relative, and below int256.max / 1e50 times it when
        // relative, as a + b is at least 1e50.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedCoefficient = int256(
            LibDecimalFloatImplementation.mulDiv(
                difference, LibDecimalFloatImplementation.mulDiv(series, 2 * POW_FIXED_ONE, POW_FIXED_LN10), sum
            )
        );
        return (below ? -signedCoefficient : signedCoefficient, exponent);
    }
}
