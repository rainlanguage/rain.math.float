// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// Error bounds for the log table tests, scaled by 1e36.
library LibTestPrecision {
    /// Max |four figure log table error| over every four digit mantissa.
    uint256 internal constant LOG10_TABLE_MAX_ERROR = 1.2e32;
    /// Every round trip in the log10 table test is below 1e-36.
    uint256 internal constant POW_ROUND_TRIP_LIMIT = 1;
}
