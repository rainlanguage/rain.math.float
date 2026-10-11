// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev Fuzz bounds for unpacked exponents: half of int256 either side, so the
/// sum or difference of two bounded exponents does not overflow.
int256 constant EXPONENT_MAX = type(int256).max / 2;

/// @dev Negation of `EXPONENT_MAX`.
int256 constant EXPONENT_MIN = -EXPONENT_MAX;
