// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Float} from "../lib/LibDecimalFloat.sol";

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

/// @dev Thrown by a lossless conversion to a Float when the value is not
/// exactly a Float and is not past the largest one, which is
/// `ExponentOverflow`. A value smaller than every Float is this error.
error LossyConversionToFloat(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when converting a float to some value when the conversion
/// is lossy.
error LossyConversionFromFloat(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when `log10Ratio` is asked for a relative log with a + b below
/// 1e50, where its result is unproven or overflows.
/// @param a The numerator.
/// @param b The denominator.
error Log10RatioRelativeSumTooSmall(uint256 a, uint256 b);

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

/// @dev Thrown when attempting to raise a negative base to a fractional power.
error PowNegativeBase(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when `agree` is given a negative tolerance. A spread is a
/// distance and so is never negative, which leaves nothing a negative
/// tolerance could express. Without this revert it would be silently dominated
/// by the other term, because the limit is the LARGER of the two, so a
/// closeness check built on a malformed tolerance would pass as though it were
/// well formed.
/// @param absolute The absolute tolerance as given.
/// @param proportional The proportional tolerance as given.
error AgreeToleranceNegative(Float absolute, Float proportional);

/// @dev Thrown when neither tolerance given to `agree` is positive. The limit
/// is then zero and `agree` degenerates into exact equality, which `eq`
/// already answers more cheaply and more clearly. Without this revert a caller
/// that meant to set a tolerance and set none would get a check that only ever
/// accepts identical values. Either tolerance ALONE may be zero; that is how a
/// caller asks for only the other one.
/// @param absolute The absolute tolerance as given.
/// @param proportional The proportional tolerance as given.
error AgreeNoPositiveTolerance(Float absolute, Float proportional);

/// @dev Thrown when `agree` is given a `lowest` above its `highest`. The
/// spread `highest - lowest` is then negative, so it is within every valid
/// limit. Without this revert every reversed pair would agree, however far
/// apart.
/// @param lowest The lowest value as given.
/// @param highest The highest value as given.
error AgreeUnordered(Float lowest, Float highest);

/// @dev Thrown when `log10Ratio` is given a + b past `uint256.max`, b of zero,
/// or z = |a - b| / (a + b) at 1e-50 with z^16 of at least 1e-50, past which
/// its series is not proven.
/// @param a The numerator.
/// @param b The denominator.
error Log10RatioOutOfRange(uint256 a, uint256 b);

/// @dev Thrown when `sqrt` is given a coefficient outside (0, 1e76), or an
/// exponent so close to `int256.min` that scaling the coefficient and
/// evening the exponent would pass it.
/// @param signedCoefficient The coefficient as given.
/// @param exponent The exponent as given.
error SqrtOutOfRange(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when `exp10Fixed` is given an exponent outside [0, 1) at the
/// 1e50 scale.
/// @param x The exponent as given.
error Exp10FixedOutOfRange(uint256 x);

/// @dev Thrown when `log10Reduce` is given a value outside [1e75, 1e76).
/// @param x The value as given.
error Log10ReduceOutOfRange(uint256 x);

/// @dev Thrown when `absCoefficient` is given `int256.min`, whose magnitude
/// does not fit an int256.
/// @param signedCoefficient The coefficient as given.
error AbsCoefficientOverflow(int256 signedCoefficient);

/// @dev Thrown when `scaleUp` is given a coefficient outside (0, 1e76), or an
/// exponent the shift into [1e75, 1e76) would take past `type(int256).min`.
/// @param signedCoefficient The coefficient as given.
/// @param exponent The exponent as given.
error ScaleUpOutOfRange(int256 signedCoefficient, int256 exponent);
