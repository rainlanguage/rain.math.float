// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// Error bounds for the table based transcendental functions, scaled by 1e36.
library LibTestPrecision {
    /// Max |log10 error| over every four digit mantissa.
    uint256 internal constant LOG10_TABLE_MAX_ERROR = 1.2e32;
    /// LibDecimalFloatPowTest diffLimit.
    uint256 internal constant POW_ROUND_TRIP_LIMIT = 0.09e36;
    // The bounds below are the worst seen over about 250k fuzz runs each, plus
    // a margin.
    uint256 internal constant LOG10_MAX_ERROR = 1.5e32;
    uint256 internal constant LOG10_PRODUCT_MAX_ERROR = 4e32;
    uint256 internal constant LOG10_MONOTONE_MAX_DROP = 1e30;
    uint256 internal constant POW10_MAX_ERROR = 1.2e33;
    uint256 internal constant POW10_TABLE_MAX_ERROR = 1e33;
    uint256 internal constant POW10_TABLE_MAX_ERROR_MEASURED = 892379846881595944137320792921943;
    uint256 internal constant POW10_GRID_MAX_DROP_MEASURED = 823723228995057660626029654036243;
    uint256 internal constant POW10_MONOTONE_MAX_DROP = 1.2e33;
    uint256 internal constant POW10_LOG10_MAX_ERROR = 1.5e33;
    uint256 internal constant POW_MAX_ERROR = 1.5e33;
    uint256 internal constant POW_PRODUCT_MAX_ERROR = 3e33;
    uint256 internal constant POW_MONOTONE_MAX_DROP = 1.2e33;
    uint256 internal constant SQRT_MAX_ERROR = 1.5e33;
    uint256 internal constant SQRT_SQUARE_MAX_ERROR = 3e33;
    uint256 internal constant SQRT_MONOTONE_MAX_DROP = 1.2e33;
}
