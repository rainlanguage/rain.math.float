// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Float} from "../lib/LibDecimalFloat.sol";

/// @dev Thrown when a value is past every Float, or an exponent passes
/// int256. `div`, `inv`, `pow` and `pow10` report the Float they were called
/// with. Every other public operation, `packLossy` and `packLossless` report
/// the unpacked value handed to packing. The implementation's `add`, `sub`,
/// `mul` and `div` report their first operand where an exponent passes
/// int256; `log10Unrounded`, `minus` and `roundSignificant` their input.
/// `LibParseDecimalFloat` returns the selector by value and never reverts
/// with it.
/// @param signedCoefficient The signed coefficient of the value reported.
/// @param exponent The exponent of the value reported.
error ExponentOverflow(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when a non-zero result is below every non-zero Float, so that
/// the closest Float toward zero would be zero: magnitude below
/// 1e-2147483648 (e.g. `mul` of 1e-2147483648 by 0.1). Returning `FLOAT_ZERO`
/// instead would break code that branches on `result == 0`.
/// @param signedCoefficient The signed coefficient of the value reported:
/// the unpacked result handed to `packArithmeticResult` by the operations it
/// finalises, or the Float `div`, `inv`, `pow` or `pow10` was called with.
/// @param exponent The exponent of the value reported.
error ExponentUnderflow(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when attempting to convert a negative number to an unsigned
/// fixed-point number.
/// @param signedCoefficient The negative coefficient as given.
/// @param exponent The exponent as given.
error NegativeFixedDecimalConversion(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when converting a Float to a fixed-decimal uint256 and the
/// scaled value exceeds `uint256.max`. Returning a silent zero with
/// `lossless=false` would decapitate the high bits of the value;
/// reverting surfaces the overflow with the original inputs so callers can
/// rescale or reject.
/// @param signedCoefficient The coefficient as given.
/// @param exponent The exponent as given.
/// @param decimals The target decimals as given.
error FixedDecimalOverflow(int256 signedCoefficient, int256 exponent, uint8 decimals);

/// @dev Thrown when attempting to calculate the log of 0.
error Log10Zero();

/// @dev Thrown when attempting to calculate the log of a negative number.
/// @param signedCoefficient The negative coefficient as given.
/// @param exponent The exponent as given.
error Log10Negative(int256 signedCoefficient, int256 exponent);

/// @dev Thrown by a lossless conversion to a Float when the value is not
/// exactly a Float and is not past the largest one, which is
/// `ExponentOverflow`. A value smaller than every Float is this error.
/// @param signedCoefficient The coefficient of the value: `packLossless`'s
/// input, or `fromFixedDecimalLossy`'s result for the fixed-decimal
/// conversions.
/// @param exponent The exponent of that same value.
error LossyConversionToFloat(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when converting a float to some value when the conversion
/// is lossy.
/// @param signedCoefficient The signed coefficient of the Float converted.
/// @param exponent The exponent of the Float converted.
error LossyConversionFromFloat(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when `log10Ratio` is asked for a relative log with a + b below
/// 1e50, where its result is unproven or overflows. A relative b of zero with
/// a below 1e50 is this error, not `Log10RatioOutOfRange`.
/// @param a The numerator.
/// @param b The denominator.
error Log10RatioRelativeSumTooSmall(uint256 a, uint256 b);

/// @dev Thrown when attempting to exponentiate 0^b where b is negative.
/// @param b The negative power as given.
error ZeroNegativePower(Float b);

/// @dev Thrown by the implementation's `mulDiv`, which `div`, `sqrt` and
/// `log10Ratio` call, when floor(x y / denominator) is 2^256 or more or
/// `denominator` is zero, and by `mulDivFixed` when floor(x y / 1e50) is
/// 2^256 or more.
/// @param x The first factor.
/// @param y The second factor.
/// @param denominator The divisor, `POW_FIXED_ONE` from `mulDivFixed`.
error MulDivOverflow(uint256 x, uint256 y, uint256 denominator);

/// @dev Thrown by `maximizeFull` when the shift that maximizes the
/// coefficient would take the exponent below `type(int256).min`, where
/// `maximize` instead stops at the floor and reports the shortfall.
/// @param signedCoefficient The coefficient as given.
/// @param exponent The exponent as given.
error MaximizeOverflow(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when dividing by zero. `div` reports its dividend; the public
/// `inv` reports the zero it was asked to invert, and the implementation's
/// `inv` its dividend, one as `1e76 × 10^-76`.
/// @param signedCoefficient The signed coefficient of the dividend for
/// `div`, of the inverted zero for the public `inv`.
/// @param exponent The exponent of that same value.
error DivisionByZero(int256 signedCoefficient, int256 exponent);

/// @dev Thrown when raising a negative base to a fractional power, and by
/// `sqrt` of a negative.
/// @param signedCoefficient The base's signed coefficient, unpacked.
/// @param exponent The base's exponent.
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

/// @dev Thrown when `log10Ratio` is given a + b past `uint256.max`, b of zero,
/// or z = |a - b| / (a + b) at 1e-50 with z^16 of at least 1e-50, past which
/// its series is not proven. A relative a + b below 1e50 is
/// `Log10RatioRelativeSumTooSmall` instead, b of zero included.
/// @param a The numerator.
/// @param b The denominator.
error Log10RatioOutOfRange(uint256 a, uint256 b);

/// @dev Thrown when `sqrt` is given a coefficient outside (0, 1e76).
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

/// @dev Thrown by `withTargetExponent` when growing the coefficient to the
/// target exponent takes it outside int256.
/// @param signedCoefficient The coefficient as given.
/// @param exponent The exponent as given.
/// @param targetExponent The target exponent as given.
error WithTargetExponentOverflow(int256 signedCoefficient, int256 exponent, int256 targetExponent);

/// @dev Thrown by `unabsUnsignedMulOrDivLossy` when a magnitude that does not
/// fit int256 at the result's sign must shed a digit at exponent
/// `type(int256).max`. `mul` and `div` revert `ExponentOverflow` before they
/// pass it such an input.
/// @param a The signed coefficient of the first operand.
/// @param b The signed coefficient of the second operand.
/// @param signedCoefficientAbs The magnitude of the result coefficient.
/// @param exponent The exponent of the result.
error UnabsExponentOverflow(int256 a, int256 b, uint256 signedCoefficientAbs, int256 exponent);
