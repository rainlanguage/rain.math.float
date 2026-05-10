// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Float} from "../lib/LibDecimalFloat.sol";

/// @dev Thrown when a coefficient overflows.
error CoefficientOverflow(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when an exponent overflows.
error ExponentOverflow(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when an exponent underflows. Exponent underflow means the
/// magnitude is smaller than any representable Float. Without this revert,
/// arithmetic ops that compose to underflow (e.g. `mul` with two operands
/// whose exponents sum below `int32.min`) would silently return `FLOAT_ZERO`,
/// breaking downstream code that branches on `result == 0`.
error ExponentUnderflow(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when attempting to convert a negative number to an unsigned
/// fixed-point number.
error NegativeFixedDecimalConversion(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when converting a Float to a fixed-decimal uint256 and the
/// scaled value exceeds `uint256.max`. Returning a silent zero with
/// `lossless=false` would decapitate the high bits of the value;
/// reverting surfaces the overflow with the original inputs so callers can
/// rescale or reject.
error FixedDecimalOverflow(int256 signedCoefficient, int256 exponent, uint8 decimals);

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

/// @dev Thrown when scientificMin is not less than scientificMax in format.
/// @param scientificMin The minimum threshold for scientific notation.
/// @param scientificMax The maximum threshold for scientific notation.
error ScientificMinNotLessThanMax(Float scientificMin, Float scientificMax);

/// @dev Thrown when constructing a `DecimalFloat` on a chain where the
/// log tables data contract is not deployed at the expected address with
/// the expected codehash. Without this check, transcendental functions
/// (`pow10`/`log10`/`pow`/`sqrt`) would silently `extcodecopy` zero bytes
/// and return garbage.
/// @param tablesAddress The address `DecimalFloat` was compiled to read
/// log tables from.
/// @param expectedCodehash The codehash the deployed table contract is
/// expected to have.
/// @param actualCodehash The codehash currently at `tablesAddress` (zero
/// if no contract is deployed there).
error LogTablesNotDeployed(address tablesAddress, bytes32 expectedCodehash, bytes32 actualCodehash);
