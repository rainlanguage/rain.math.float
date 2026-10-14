// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// Maps fuzz inputs onto the regions a uniform int256 draw almost never
/// reaches, for region-weighted fuzzes beside the full-domain ones.
library LibTestRegion {
    /// An exponent within 76 of `exponent`, the window where comparisons
    /// rescale: `exponent + delta` for `delta = offset % 77`, or
    /// `exponent - delta` where `exponent + delta` leaves int256.
    function nearExponent(int256 exponent, int256 offset) internal pure returns (int256) {
        int256 delta = offset % 77;
        if ((delta > 0 && exponent > type(int256).max - delta) || (delta < 0 && exponent < type(int256).min - delta)) {
            delta = -delta;
        }
        return exponent + delta;
    }

    /// `signedCoefficient` with `drop % 77` low digits dropped, so the digit
    /// count spreads over every length rather than sitting at 77.
    function anyDigits(int256 signedCoefficient, uint256 drop) internal pure returns (int256) {
        // Safe: 10^76 fits int256.
        // forge-lint: disable-next-line(unsafe-typecast)
        return signedCoefficient / int256(10 ** (drop % 77));
    }

    /// An int32 exponent within `maxLift` of the int32 floor,
    /// `type(int32).min + lift % (maxLift + 1)`.
    function nearInt32Floor(uint256 lift, uint256 maxLift) internal pure returns (int256) {
        // Safe: the lift is at most `maxLift`, which callers keep small.
        // forge-lint: disable-next-line(unsafe-typecast)
        return int256(type(int32).min) + int256(lift % (maxLift + 1));
    }
}
