// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// Error bounds for the table based transcendental functions, scaled by 1e36.
library LibTestPrecision {
    /// Max |log10 error| over every four digit mantissa.
    uint256 internal constant LOG10_TABLE_MAX_ERROR = 1.2e32;
    /// LibDecimalFloatPowTest diffLimit.
    uint256 internal constant POW_ROUND_TRIP_LIMIT = 0.09e36;
}
