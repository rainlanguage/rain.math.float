// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// Error bounds for the transcendental functions, scaled by 1e36.
///
/// Against LibTestTranscendental each bound is the library's proven error plus
/// the reference's proven error, 4.5e-35 absolute for log10 and 4.2e-34
/// relative for pow10. log10 and pow10 are correctly rounded to 41 digits, so
/// within half a unit, 5e-41 relative. A leg of pow or sqrt is within
/// 5.00006e-41 relative: half a unit, plus log10Unrounded's 2.245e-47 times a
/// fraction below 1 and ln 10, plus the packing.
library LibTestPrecision {
    /// Max |four figure log table error| over every four digit mantissa.
    uint256 internal constant LOG10_TABLE_MAX_ERROR = 1.2e32;
    /// Every round trip in the log10 table test is below 1e-36.
    uint256 internal constant POW_ROUND_TRIP_LIMIT = 1;
    /// Half a unit at 41 digits of a log below 1e10, 5e-32, plus the
    /// reference.
    uint256 internal constant LOG10_MAX_ERROR = 50045;
    /// Three logs below 1e3 rounded, each within 5e-39, summed exactly.
    uint256 internal constant LOG10_PRODUCT_MAX_ERROR = 1;
    /// The reference, plus half a unit, over 1 - 4.2e-34.
    uint256 internal constant POW10_MAX_ERROR = 421;
    /// log10 of a base below 1e140 within 5e-39, 1.16e-38 relative through
    /// pow10, plus its half unit.
    uint256 internal constant POW10_LOG10_MAX_ERROR = 1;
    /// The reference log10 error times |b| up to 1e6 and ln 10, 1.0362e-28,
    /// plus the reference pow10 error and a leg.
    uint256 internal constant POW_MAX_ERROR = 1.0363e8;
    /// Three legs.
    uint256 internal constant POW_PRODUCT_MAX_ERROR = 1;
    /// Half the reference log10 error times ln 10, 5.181e-35, plus the
    /// reference pow10 error and a leg.
    uint256 internal constant SQRT_MAX_ERROR = 472;
    /// Twice a leg.
    uint256 internal constant SQRT_SQUARE_MAX_ERROR = 1;
}
