// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// log10 in 1e36 fixed point from series, independent of the log tables, as
/// the truth the log tables are measured against.
library LibTestTranscendental {
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
}
