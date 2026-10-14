// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev Thrown by non-scientific `toDecimalString` when the canonical
/// exponent, after the coefficient's trailing zeros, is outside
/// `[-MAX_NON_SCIENTIFIC_EXPONENT, MAX_NON_SCIENTIFIC_EXPONENT]`. Scientific
/// mode never throws it.
/// @param exponent The canonical exponent.
error UnformatableExponent(int256 exponent);
