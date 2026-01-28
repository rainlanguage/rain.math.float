// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Float} from "../lib/LibDecimalFloat.sol";

/// @dev Thrown when a coefficient overflows.
error CoefficientOverflow(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when an exponent overflows.
error ExponentOverflow(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when attempting to convert a negative number to an unsigned
/// fixed-point number.
error NegativeFixedDecimalConversion(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when attempting to calculate the log of 0.
error Log10Zero();

/// @dev Thrown when attempting to calculate the log of a negative number.
error Log10Negative(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when converting some value to a float when the conversion
/// is lossy.
error LossyConversionToFloat(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when converting a float to some value when the conversion
/// is lossy.
error LossyConversionFromFloat(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when attempting to exponentiate 0^b where b is negative.
error ZeroNegativePower(Float b);

/// @dev Thrown when mulDiv internal to division overflows.
error MulDivOverflow(uint256 x, uint256 y, uint256 denominator);

/// @dev Thrown when a maximize overflows where it is not appropriate.
error MaximizeOverflow(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when dividing by zero.
/// @param signedCoefficient The signed coefficient of the numerator.
/// @param exponent The exponent of the numerator.
error DivisionByZero(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when attempting to exponentiate a negative base.
error PowNegativeBase(int256 signedCoefficient, int256 exponent);

/// @dev Thrown if writing the data by creating the contract fails somehow.
error WriteError();
