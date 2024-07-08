// SPDX-License-Identifier: CAL
pragma solidity ^0.8.25;

/// @dev Thrown when an exponent overflows.
error ExponentOverflow(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when attempting to convert a negative number to an unsigned
/// fixed-point number.
error NegativeFixedDecimalConversion(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when attempting to calculate the log of 0.
error Log10Zero();

/// @dev Thrown when attempting to calculate the log of a negative number.
error Log10Negative(int256 signedCoefficient, int256 exponent);
