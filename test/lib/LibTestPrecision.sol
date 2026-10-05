// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// Error bounds for the transcendental functions, scaled by 1e36.
library LibTestPrecision {
    /// Max |four figure log table error| over every four digit mantissa.
    uint256 internal constant LOG10_TABLE_MAX_ERROR = 1.2e32;
    /// Every round trip in the log10 table test is below 1e-36.
    uint256 internal constant POW_ROUND_TRIP_LIMIT = 1;
    // Against LibTestTranscendental the library's 41 digit error is far below
    // the reference's own 1e36 fixed point truncation, so the reference bounds
    // the bounds below. pow10's grid measures the reference at 1.04e-34
    // relative, past the 1e-34 it documents. A comparison between the
    // library's own outputs has no reference error and is within one unit.
    /// Half a unit at 41 digits of a log up to 2.2e9, plus the reference.
    uint256 internal constant LOG10_MAX_ERROR = 5.01e4;
    uint256 internal constant LOG10_PRODUCT_MAX_ERROR = 1;
    uint256 internal constant LOG10_MONOTONE_MAX_DROP = 0;
    /// The reference pow10 error, five times its grid worst.
    uint256 internal constant POW10_MAX_ERROR = 5e2;
    uint256 internal constant POW10_GRID_MAX_ERROR_MEASURED = 104;
    uint256 internal constant POW10_MONOTONE_MAX_DROP = 0;
    uint256 internal constant POW10_LOG10_MAX_ERROR = 1;
    /// The reference log10 error times |b| up to 1e6 and ln 10, plus the
    /// reference pow10 error.
    uint256 internal constant POW_MAX_ERROR = 1.62e8;
    uint256 internal constant POW_PRODUCT_MAX_ERROR = 1;
    uint256 internal constant POW_MONOTONE_MAX_DROP = 0;
    /// Half the reference log10 error times ln 10, plus the reference pow10
    /// error.
    uint256 internal constant SQRT_MAX_ERROR = 5.81e2;
    uint256 internal constant SQRT_SQUARE_MAX_ERROR = 1;
    uint256 internal constant SQRT_MONOTONE_MAX_DROP = 0;
}
