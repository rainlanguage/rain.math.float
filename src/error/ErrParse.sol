// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev Returned by value from `LibParseDecimalFloat`, never reverted with,
/// for a `.` without fraction digits.
/// @param position The cursor after the `.`, which a reverting caller appends.
error MalformedDecimalPoint(uint256 position);

/// @dev Returned by value from `LibParseDecimalFloat`, never reverted with,
/// for an `e` or `E` without exponent digits.
/// @param position The cursor where the exponent digits were expected, which
/// a reverting caller appends.
error MalformedExponentDigits(uint256 position);

/// @dev Returned by value from `LibParseDecimalFloat`, never reverted with,
/// for a well formed literal that is not exactly a Float and is below
/// `(2^223 + 2) × 10^int32.max` in magnitude: too many significant digits, a
/// significant digit below `10^int32.min` (`1.5e-2147483648`, and every
/// nonzero value below every nonzero Float, such as `1e-2147483649`), or past
/// the largest Float of its sign.
/// @param position The cursor after the literal, from
/// `parseDecimalFloatInline`, which a reverting caller appends.
/// `parseDecimalFloat` returns no position.
error ParseDecimalPrecisionLoss(uint256 position);

/// @dev Returned by value from `parseDecimalFloat`, never reverted with, for
/// a well formed literal followed by more characters.
error ParseDecimalFloatExcessCharacters();

/// @dev Thrown when the parser reads the significant digits of a mantissa
/// that has none. Unreachable: only a literal with a nonzero digit is read so.
/// @param start The start of the literal.
error ParseDecimalNoSignificantDigits(uint256 start);
