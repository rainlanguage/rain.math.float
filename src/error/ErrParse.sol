// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 thedavidmeister
pragma solidity ^0.8.25;

/// @dev Thrown when the decimal point is malformed in a float string.
/// @param position The position in the string where the error occurred.
error MalformedDecimalPoint(uint256 position);

/// @dev Thrown when the exponent cannot be parsed from a float string.
/// @param position The position in the string where the error occurred.
error MalformedExponentDigits(uint256 position);

/// @dev Thrown when parsing a decimal string would result in precision loss in
/// the decimal float representation.
/// @param position The position in the string where the error occurred.
error ParseDecimalPrecisionLoss(uint256 position);
