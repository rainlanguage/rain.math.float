// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev 1/9 truncated at int256 precision, `10^76 / 9`: 76 ones.
int256 constant ONES = 1111111111111111111111111111111111111111111111111111111111111111111111111111;
/// @dev 1/3 truncated at Float precision, `10^67 / 3`: 67 threes, the most
/// an int224 coefficient holds.
int256 constant THREES_PACKED = 3333333333333333333333333333333333333333333333333333333333333333333;
/// @dev 1/3 truncated at int256 precision, `10^76 / 3`: 76 threes.
int256 constant THREES = 3333333333333333333333333333333333333333333333333333333333333333333333333333;
