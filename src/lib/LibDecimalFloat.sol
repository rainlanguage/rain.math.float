// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    ExponentOverflow,
    CoefficientOverflow,
    NegativeFixedDecimalConversion,
    LossyConversionFromFloat,
    LossyConversionToFloat,
    ZeroNegativePower,
    PowNegativeBase
} from "../error/ErrDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "./implementation/LibDecimalFloatImplementation.sol";

type Float is bytes32;

/// @title LibDecimalFloat
/// Floating point math library for Rainlang.
/// Broadly implements decimal floating point math with 224 signed bits for the
/// coefficient and 32 signed bits for the exponent. Notably the implementation
/// differs from standard specifications in a few key areas:
///
/// - There is no concept of NaN or Infinity.
/// - There is no concept of rounding modes.
/// - There is no negative zero.
/// - This is a decimal floating point library, not binary.
///
/// This means that operations such as divide by 0 will revert, rather than
/// produce nonsense like NaN or Infinity. This is a deliberate design choice
/// to make the library more predictable and easier to reason about as the basis
/// of a defi native smart contract language.
///
/// The reason that this is a decimal floating point system is that the inputs
/// to the system as rainlang literals are decimal values. This means that `0.1`
/// has an _exact_ representation in the system, rather than a repeating binary
/// fraction. This technically results in less precision than a binary floating
/// point system, but is much more predictable and easier to reason about in the
/// context of financial inputs and outputs, which are typically all decimal
/// values as understood by humans. However, consider that we have 224 bits of
/// precision in the coefficient, which is far more than the 53 bits of a double
/// precision floating point number regardless of binary/decimal considerations,
/// and should be more than enough for most defi use cases.
library LibDecimalFloat {
    using LibDecimalFloat for Float;

    address constant LOG_TABLES_ADDRESS = 0xdc564999251875a2728Eec15962c5456C9259f54;

    /// A zero valued float.
    Float constant FLOAT_ZERO = Float.wrap(0);

    /// A one valued float.
    Float constant FLOAT_ONE = Float.wrap(bytes32(uint256(1)));

    /// A half valued float.
    // slither-disable-next-line too-many-digits
    Float constant FLOAT_HALF =
        Float.wrap(bytes32(uint256(0xffffffff00000000000000000000000000000000000000000000000000000005)));

    /// A two valued float.
    Float constant FLOAT_TWO = Float.wrap(bytes32(uint256(0x02)));

    /// Largest possible positive value.
    /// type(int224).max, type(int32).max
    Float constant FLOAT_MAX_POSITIVE_VALUE =
        Float.wrap(bytes32(uint256(0x7fffffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffff)));

    /// Smallest possible positive value.
    /// 1, type(int32).min
    // slither-disable-next-line too-many-digits
    Float constant FLOAT_MIN_POSITIVE_VALUE =
        Float.wrap(bytes32(uint256(0x8000000000000000000000000000000000000000000000000000000000000001)));

    /// Largest possible (closest to zero) negative value.
    /// -1, type(int32).min
    // slither-disable-next-line too-many-digits
    Float constant FLOAT_MAX_NEGATIVE_VALUE =
        Float.wrap(bytes32(uint256(0x80000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffff)));

    /// Smallest possible (most negative) negative value.
    /// type (int224).min, type(int32).max
    // slither-disable-next-line too-many-digits
    Float constant FLOAT_MIN_NEGATIVE_VALUE =
        Float.wrap(bytes32(uint256(0x7fffffff80000000000000000000000000000000000000000000000000000000)));

    /// Euler's number
    /// 2.718281828459045235360287471352662497757247093699959574966967627724e66, -66
    Float constant FLOAT_E =
        Float.wrap(bytes32(uint256(0xffffffbe19cfc6ef4f44cf88f14500d013df534fcaad48fca1d5ca47bea26fcc)));

    /// Convert a fixed point decimal value to a signed coefficient and exponent.
    /// The conversion can be lossy if the unsigned value is too large to fit in
    /// the signed coefficient.
    /// @param value The fixed point decimal value to convert.
    /// @param decimals The number of decimals in the fixed point representation.
    /// e.g. If 1e18 represents 1 this would be 18 decimals.
    /// @return signedCoefficient The signed coefficient of the floating point
    /// representation.
    /// @return exponent The exponent of the floating point representation.
    /// @return lossless `true` if the conversion is lossless.
    function fromFixedDecimalLossy(uint256 value, uint8 decimals) internal pure returns (int256, int256, bool) {
        unchecked {
            int256 exponent = -int256(uint256(decimals));

            // Catch an edge case where unsigned value looks like a negative
            // value when coerced.
            if (value > uint256(type(int256).max)) {
                // value is divided by 10 so won't truncate when cast.
                // forge-lint: disable-next-line(unsafe-typecast)
                return (int256(value / 10), exponent + 1, value % 10 == 0);
            } else {
                // case that would truncate is handled above.
                // forge-lint: disable-next-line(unsafe-typecast)
                return (int256(value), exponent, true);
            }
        }
    }

    /// Same as fromFixedDecimalLossy, but returns a Float struct instead of
    /// separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param value The fixed point decimal value to convert.
    /// @param decimals The number of decimals in the fixed point representation.
    /// e.g. If 1e18 represents 1 this would be 18 decimals.
    /// @return float The Float struct containing the signed coefficient and
    /// exponent.
    /// @return lossless `true` if the conversion is lossless.
    function fromFixedDecimalLossyPacked(uint256 value, uint8 decimals) internal pure returns (Float, bool) {
        (int256 signedCoefficient, int256 exponent, bool lossless) = fromFixedDecimalLossy(value, decimals);
        (Float float, bool losslessPack) = packLossy(signedCoefficient, exponent);
        return (float, lossless && losslessPack);
    }

    /// Lossless version of `fromFixedDecimalLossy`. This will revert if the
    /// conversion is lossy.
    /// @param value As per `fromFixedDecimalLossy`.
    /// @param decimals As per `fromFixedDecimalLossy`.
    /// @return signedCoefficient As per `fromFixedDecimalLossy`.
    /// @return exponent As per `fromFixedDecimalLossy`.
    function fromFixedDecimalLossless(uint256 value, uint8 decimals) internal pure returns (int256, int256) {
        (int256 signedCoefficient, int256 exponent, bool lossless) = fromFixedDecimalLossy(value, decimals);
        if (!lossless) {
            revert LossyConversionToFloat(signedCoefficient, exponent);
        }
        return (signedCoefficient, exponent);
    }

    /// Lossless version of `fromFixedDecimalLossyMem`. This will revert if the
    /// conversion is lossy.
    /// @param value As per `fromFixedDecimalLossyMem`.
    /// @param decimals As per `fromFixedDecimalLossyMem`.
    /// @return float The Float struct containing the signed coefficient and
    /// exponent.
    function fromFixedDecimalLosslessPacked(uint256 value, uint8 decimals) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = fromFixedDecimalLossless(value, decimals);
        return packLossless(signedCoefficient, exponent);
    }

    /// Convert a signed coefficient and exponent to a fixed point decimal value.
    /// The conversion is impossible and will revert if the signed coefficient is
    /// negative. If the conversion overflows it will also revert.
    /// The conversion can be lossy if the floating point representation is not
    /// able to fit in the fixed point representation, and will truncate
    /// precision.
    /// @param signedCoefficient The signed coefficient of the floating point
    /// representation.
    /// @param exponent The exponent of the floating point representation.
    /// @param decimals The number of decimals in the fixed point representation.
    /// e.g. If 1e18 represents 1 this would be 18 decimals.
    /// @return value The fixed point decimal value.
    /// @return lossless `true` if the conversion is lossless.
    function toFixedDecimalLossy(int256 signedCoefficient, int256 exponent, uint8 decimals)
        internal
        pure
        returns (uint256, bool)
    {
        // The output type is uint256, so we can't represent negative numbers.
        if (signedCoefficient < 0) {
            revert NegativeFixedDecimalConversion(signedCoefficient, exponent);
        }
        // Zero is always 0 and neither exponent nor decimals matter.
        else if (signedCoefficient == 0) {
            return (0, true);
        } else {
            // Safe to do this conversion because we revert above on negative.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 unsignedCoefficient = uint256(signedCoefficient);
            int256 finalExponent;

            // Ye olde "safe math" to give a better error if this edge case
            // overflow is ever hit. Normal use should never overflow here.
            unchecked {
                finalExponent = exponent + int256(uint256(decimals));
                if (finalExponent < exponent) {
                    revert ExponentOverflow(signedCoefficient, exponent);
                }
            }

            uint256 scale;
            uint256 fixedDecimal;
            if (finalExponent < 0) {
                unchecked {
                    // Every possible value rounds to 0 if the exponent is less
                    // than -77. This is always lossless as we know the value is
                    // is not zero in real.
                    if (finalExponent < -77) {
                        return (0, false);
                    }

                    // At this point, scale cannot revert, so it is safe to do
                    // this unchecked.
                    // finalExponent is negative here so making it absolute will
                    // always fit in uint256.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    scale = 10 ** uint256(-finalExponent);
                    fixedDecimal = unsignedCoefficient / scale;

                    // Slither false positive because we're explicitly checking
                    // for the lossiness that it warns about.
                    //slither-disable-next-line divide-before-multiply
                    return (fixedDecimal, fixedDecimal * scale == unsignedCoefficient);
                }
            } else if (finalExponent > 0) {
                // finalExponent is positive here.
                // forge-lint: disable-next-line(unsafe-typecast)
                scale = 10 ** uint256(finalExponent);
                fixedDecimal = unsignedCoefficient * scale;
                unchecked {
                    // This is always lossless because we're scaling up.
                    // If the value is too large to fit in a uint256, we'll
                    // revert above due to overflow.
                    return (fixedDecimal, true);
                }
            } else {
                return (unsignedCoefficient, true);
            }
        }
    }

    /// Same as toFixedDecimalLossy, but accepts a Float struct instead of
    /// separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param float The Float struct containing the signed coefficient and
    /// exponent.
    /// @param decimals The number of decimals in the fixed point representation.
    /// e.g. If 1e18 represents 1 this would be 18 decimals.
    /// @return value The fixed point decimal value.
    /// @return lossless `true` if the conversion is lossless.
    function toFixedDecimalLossy(Float float, uint8 decimals) internal pure returns (uint256, bool) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        return toFixedDecimalLossy(signedCoefficient, exponent, decimals);
    }

    /// Lossless version of `toFixedDecimalLossy`. This will revert if the
    /// conversion is lossy.
    /// @param signedCoefficient As per `toFixedDecimalLossy`.
    /// @param exponent As per `toFixedDecimalLossy`.
    /// @param decimals As per `toFixedDecimalLossy`.
    /// @return value As per `toFixedDecimalLossy`.
    function toFixedDecimalLossless(int256 signedCoefficient, int256 exponent, uint8 decimals)
        internal
        pure
        returns (uint256)
    {
        (uint256 value, bool lossless) = toFixedDecimalLossy(signedCoefficient, exponent, decimals);
        if (!lossless) {
            revert LossyConversionFromFloat(signedCoefficient, exponent);
        }
        return value;
    }

    /// Same as toFixedDecimalLossless, but accepts a Float struct instead of
    /// separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param float The Float struct containing the signed coefficient and
    /// exponent.
    /// @param decimals The number of decimals in the fixed point representation.
    /// e.g. If 1e18 represents 1 this would be 18 decimals.
    /// @return value The fixed point decimal value.
    function toFixedDecimalLossless(Float float, uint8 decimals) internal pure returns (uint256) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        return toFixedDecimalLossless(signedCoefficient, exponent, decimals);
    }

    /// Pack a signed coefficient and exponent into a single `PackedFloat`.
    /// Clearly this involves fitting 64 bytes into 32 bytes, so there will be
    /// data loss.
    /// @param signedCoefficient The signed coefficient of the floating point
    /// representation.
    /// @param exponent The exponent of the floating point representation.
    /// @return float The packed representation of the signed coefficient and
    /// exponent.
    function packLossy(int256 signedCoefficient, int256 exponent) internal pure returns (Float float, bool lossless) {
        unchecked {
            int256 initialSignedCoefficient = signedCoefficient;
            int256 initialExponent = exponent;
            // lossless is true if the signed coefficient fits in int224.
            // truncation here is intentional if it happens as that is what we
            // are testing for.
            // forge-lint: disable-next-line(unsafe-typecast)
            lossless = int224(signedCoefficient) == signedCoefficient;

            // The reason that we can do unchecked exponent addition here is that
            // when it overflows it will wrap to a very large negative number.
            // This will get caught below when we check if the exponent fits in
            // int32.
            if (!lossless) {
                if (signedCoefficient / 1e72 != 0) {
                    signedCoefficient /= 1e5;
                    exponent += 5;
                }

                // truncation here is intentional if it happens as that is what we
                // are testing for.
                // forge-lint: disable-next-line(unsafe-typecast)
                while (int224(signedCoefficient) != signedCoefficient) {
                    signedCoefficient /= 10;
                    ++exponent;
                }
            } else {
                if (signedCoefficient == 0) {
                    return (FLOAT_ZERO, true);
                }
            }

            // truncation here is intentional if it happens as that is what we
            // are testing for.
            // forge-lint: disable-next-line(unsafe-typecast)
            if (int32(exponent) != exponent) {
                // If the exponent is negative then this is a number too small
                // to pack. We return zero but it is not a lossless conversion.
                if (exponent < 0) {
                    return (FLOAT_ZERO, false);
                }
                revert ExponentOverflow(initialSignedCoefficient, initialExponent);
            }

            // Need a mask to zero out the bits that could be set to 1 if the
            // coefficient is negative.
            uint256 mask = type(uint224).max;
            assembly ("memory-safe") {
                float := or(and(signedCoefficient, mask), shl(0xe0, exponent))
            }
        }
    }

    function packLossless(int256 signedCoefficient, int256 exponent) internal pure returns (Float) {
        (Float c, bool lossless) = packLossy(signedCoefficient, exponent);
        if (!lossless) {
            revert CoefficientOverflow(signedCoefficient, exponent);
        }
        return c;
    }

    /// Unpack a packed bytes32 into a signed coefficient and exponent. This is
    /// the inverse of `pack`.
    /// @param float The packed representation of the signed coefficient and
    /// exponent.
    /// @return signedCoefficient The signed coefficient of the floating point
    /// representation.
    /// @return exponent The exponent of the floating point representation.
    function unpack(Float float) internal pure returns (int256 signedCoefficient, int256 exponent) {
        uint256 mask = type(uint224).max;
        assembly ("memory-safe") {
            signedCoefficient := signextend(27, and(float, mask))
            exponent := sar(0xe0, float)
        }
    }

    /// Same as add, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param a The Float struct containing the signed coefficient and
    /// exponent of the first floating point number.
    /// @param b The Float struct containing the signed coefficient and
    /// exponent of the second floating point number.
    function add(Float a, Float b) internal pure returns (Float) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (Float c, bool lossless) = packLossy(signedCoefficient, exponent);
        // Addition can be lossy.
        (lossless);
        return c;
    }

    /// Subtract float a from float b.
    ///
    /// This is effectively shorthand for adding the two floats with the second
    /// float negated. Therefore, the same caveats apply as for `add`.
    /// @param a The float to subtract from.
    /// @param b The float to subtract.
    function sub(Float a, Float b) internal pure returns (Float) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (int256 signedCoefficientC, int256 exponentC) =
            LibDecimalFloatImplementation.sub(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (Float c, bool lossless) = packLossy(signedCoefficientC, exponentC);
        // Subtraction can be lossy.
        (lossless);
        return c;
    }

    /// Same as minus, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param float The Float struct containing the signed coefficient and
    /// exponent of the floating point number.
    function minus(Float float) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.minus(signedCoefficient, exponent);
        (Float result, bool lossless) = packLossy(signedCoefficient, exponent);
        // Minus is a lossy operation due to the asymmetry of signed integers.
        (lossless);
        return result;
    }

    /// Returns the absolute value of a float.
    /// Identity if non-negative, negated if negative. Max negative signed value
    /// for the coefficient will be shifted one OOM so that it can be negated to
    /// a positive value.
    ///
    /// https://speleotrove.com/decimal/daops.html#refabs
    /// > abs takes one operand. If the operand is negative, the result is the
    /// > same as using the minus operation on the operand. Otherwise, the result
    /// > is the same as using the plus operation on the operand.
    /// @param float The float to take the absolute value of.
    function abs(Float float) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();

        if (signedCoefficient < 0) {
            (signedCoefficient, exponent) = LibDecimalFloatImplementation.minus(signedCoefficient, exponent);
        }

        (Float result, bool lossless) = packLossy(signedCoefficient, exponent);
        // At the limit of signed values there is the potential for a lossy
        // conversion when negating.
        (lossless);
        return result;
    }

    /// https://speleotrove.com/decimal/daops.html#refmult
    /// > multiply takes two operands. If either operand is a special value then
    /// > the general rules apply.
    /// >
    /// > Otherwise, the operands are multiplied together
    /// > (‘long multiplication’), resulting in a number which may be as long as
    /// > the sum of the lengths of the two operands, as follows:
    /// >
    /// > - The coefficient of the result, before rounding, is computed by
    /// >   multiplying together the coefficients of the operands.
    /// > - The exponent of the result, before rounding, is the sum of the
    /// >   exponents of the two operands.
    /// > - The sign of the result is the exclusive or of the signs of the
    /// >   operands.
    /// >
    /// > The result is then rounded to precision digits if necessary, counting
    /// > from the most significant digit of the result.
    /// @param a The Float struct containing the signed coefficient and
    /// exponent of the first floating point number.
    /// @param b The Float struct containing the signed coefficient and
    /// exponent of the second floating point number.
    function mul(Float a, Float b) internal pure returns (Float) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.mul(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (Float c, bool lossless) = packLossy(signedCoefficient, exponent);
        // Multiplication is typically lossless, but can be lossy in edge cases.
        (lossless);
        return c;
    }

    /// Same as divide, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param a The Float struct containing the signed coefficient and
    /// exponent of the first floating point number.
    /// @param b The Float struct containing the signed coefficient and
    /// exponent of the second floating point number.
    function div(Float a, Float b) internal pure returns (Float) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.div(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (Float c, bool lossless) = packLossy(signedCoefficient, exponent);
        // Division is often lossy because it is very easy to end up with
        // infinite decimal representations.
        (lossless);
        return c;
    }

    /// Same as inv, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param float The Float struct containing the signed coefficient and
    /// exponent of the floating point number.
    function inv(Float float) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.inv(signedCoefficient, exponent);
        (Float result, bool lossless) = packLossy(signedCoefficient, exponent);
        (lossless);
        return result;
    }

    /// Same as eq, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param a The first float to compare.
    /// @param b The second float to compare.
    function eq(Float a, Float b) internal pure returns (bool) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        return LibDecimalFloatImplementation.eq(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// Numeric less than for floats.
    /// A float is less than another if its numeric value is less than the other.
    /// For example, 1e2 is less than 1e3, and 1e2 is less than 2e2.
    /// @param a The first float to compare.
    /// @param b The second float to compare.
    function lt(Float a, Float b) internal pure returns (bool) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (signedCoefficientA, signedCoefficientB) =
            LibDecimalFloatImplementation.compareRescale(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        return signedCoefficientA < signedCoefficientB;
    }

    /// Numeric greater than for floats.
    /// A float is greater than another if its numeric value is greater than the
    /// other. For example, 1e3 is greater than 1e2, and 2e2 is greater than 1e2.
    /// @param a The first float to compare.
    /// @param b The second float to compare.
    function gt(Float a, Float b) internal pure returns (bool) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (signedCoefficientA, signedCoefficientB) =
            LibDecimalFloatImplementation.compareRescale(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        return signedCoefficientA > signedCoefficientB;
    }

    /// Numeric less than or equal to for floats.
    /// A float is less than or equal to another if its numeric value is less
    /// than or equal to the other. For example, 1e2 is less than or equal to 1e3
    /// and 1e2 is less than or equal to 1e2.
    function lte(Float a, Float b) internal pure returns (bool) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (signedCoefficientA, signedCoefficientB) =
            LibDecimalFloatImplementation.compareRescale(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        return signedCoefficientA <= signedCoefficientB;
    }

    /// Numeric greater than or equal to for floats.
    /// A float is greater than or equal to another if its numeric value is
    /// greater than or equal to the other. For example, 1e3 is greater than or
    /// equal to 1e2 and 1e2 is greater than or equal to 1e2.
    function gte(Float a, Float b) internal pure returns (bool) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (signedCoefficientA, signedCoefficientB) =
            LibDecimalFloatImplementation.compareRescale(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        return signedCoefficientA >= signedCoefficientB;
    }

    /// Fractional component of a float.
    /// @param float The float to frac.
    function frac(Float float) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        (int256 characteristic, int256 mantissa) =
            LibDecimalFloatImplementation.characteristicMantissa(signedCoefficient, exponent);
        (characteristic);
        (Float result, bool lossless) = packLossy(mantissa, exponent);
        // Frac is lossy by definition.
        (lossless);
        return result;
    }

    /// Integer component of a float.
    /// @param float The float to floor.
    function floor(Float float) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        // If the exponent is 0 or greater then the float is already an integer.
        if (exponent >= 0) {
            return float;
        }
        (int256 characteristic, int256 mantissa) =
            LibDecimalFloatImplementation.characteristicMantissa(signedCoefficient, exponent);
        (Float result, bool lossless) = packLossy(characteristic, exponent);
        // Flooring is lossy by definition.
        (lossless, mantissa);
        return result;
    }

    /// Smallest integer value greater than or equal to the float.
    /// @param float The float to ceil.
    function ceil(Float float) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        // If the exponent is 0 or greater then the float is already an integer.
        if (exponent >= 0) {
            return float;
        }
        (int256 characteristic, int256 mantissa) =
            LibDecimalFloatImplementation.characteristicMantissa(signedCoefficient, exponent);

        // If the mantissa is 0, then the float is already an integer.
        if (mantissa == 0) {
            return float;
        }
        // Truncate the fractional part when exponent < 0:
        //   mantissa < 0 (input < 0) → truncation towards zero increases the value (correct ceil).
        //   mantissa == 0 → value is already an integer.
        //   mantissa > 0 (input > 0) → truncation decreases the value, so add 1 to round up.
        else if (mantissa > 0) {
            (characteristic, exponent) = LibDecimalFloatImplementation.add(characteristic, exponent, 1e76, -76);
        }

        (Float result, bool lossless) = packLossy(characteristic, exponent);
        (lossless);
        return result;
    }

    /// Same as power10, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param float The Float struct containing the signed coefficient and
    /// exponent of the floating point number.
    /// @param tablesDataContract The address of the contract containing the
    /// logarithm tables.
    function pow10(Float float, address tablesDataContract) internal view returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        (signedCoefficient, exponent) =
            LibDecimalFloatImplementation.pow10(tablesDataContract, signedCoefficient, exponent);
        (Float result, bool lossless) = packLossy(signedCoefficient, exponent);
        // We don't care if power10 is lossy because it's an approximation
        // anyway.
        (lossless);
        return result;
    }

    /// Same as log10, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param tablesDataContract The address of the contract containing the
    /// logarithm tables.
    /// @param a The float to log10.
    function log10(Float a, address tablesDataContract) internal view returns (Float) {
        (int256 signedCoefficient, int256 exponent) = a.unpack();
        (signedCoefficient, exponent) =
            LibDecimalFloatImplementation.log10(tablesDataContract, signedCoefficient, exponent);
        (Float result, bool lossless) = packLossy(signedCoefficient, exponent);
        // We don't care if log10 is lossy because it's an approximation anyway.
        (lossless);
        return result;
    }

    /// a^b = 10^(b * log10(a))
    ///
    /// Due to the inaccuraces of log10 and power10, this is not perfectly
    /// accurate, a round trip like x^y^(1/y) will typically be within half a
    /// percent or less of the original value, but this can vary depending on
    /// the input values.
    ///
    /// Doesn't lose precision due to the exponent, for a wide range of
    /// exponents.
    /// @param a The float `a` in `a^b`.
    /// @param b The float `b` in `a^b`.
    /// @param tablesDataContract The address of the contract containing the
    /// logarithm tables.
    function pow(Float a, Float b, address tablesDataContract) internal view returns (Float) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();

        if (b.isZero()) {
            return FLOAT_ONE;
        } else if (signedCoefficientA <= 0) {
            if (signedCoefficientA == 0) {
                if (b.lt(FLOAT_ZERO)) {
                    // If b is negative, and a is 0, so we revert.
                    revert ZeroNegativePower(b);
                }

                // If a is zero, then a^b is always zero, regardless of b.
                // This is a special case because log10(0) is undefined.
                return FLOAT_ZERO;
            } else {
                revert PowNegativeBase(signedCoefficientA, exponentA);
            }
        }
        // Handle identity case for positive values of a, i.e. a^1.
        else if (b.eq(FLOAT_ONE) && a.gt(FLOAT_ZERO)) {
            return a;
        } else if (b.lt(FLOAT_ZERO)) {
            return pow(a.inv(), b.minus(), tablesDataContract);
        }

        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (int256 characteristicB, int256 mantissaB) =
            LibDecimalFloatImplementation.characteristicMantissa(signedCoefficientB, exponentB);

        uint256 exponentBInteger =
            uint256(LibDecimalFloatImplementation.withTargetExponent(characteristicB, exponentB, 0));

        // Exponentiation by squaring.
        (int256 signedCoefficientResult, int256 exponentResult) = (1, 0);
        (int256 signedCoefficientBase, int256 exponentBase) = a.unpack();
        while (exponentBInteger >= 1) {
            if (exponentBInteger & 0x01 == 0x01) {
                (signedCoefficientResult, exponentResult) = LibDecimalFloatImplementation.mul(
                    signedCoefficientResult, exponentResult, signedCoefficientBase, exponentBase
                );
            }
            exponentBInteger >>= 1;
            (signedCoefficientBase, exponentBase) = LibDecimalFloatImplementation.mul(
                signedCoefficientBase, exponentBase, signedCoefficientBase, exponentBase
            );
        }

        (int256 signedCoefficientC, int256 exponentC) =
            LibDecimalFloatImplementation.log10(tablesDataContract, signedCoefficientA, exponentA);

        (signedCoefficientC, exponentC) =
            LibDecimalFloatImplementation.mul(signedCoefficientC, exponentC, mantissaB, exponentB);

        (signedCoefficientC, exponentC) =
            LibDecimalFloatImplementation.pow10(tablesDataContract, signedCoefficientC, exponentC);

        (signedCoefficientC, exponentC) =
            LibDecimalFloatImplementation.mul(signedCoefficientC, exponentC, signedCoefficientResult, exponentResult);

        (Float c, bool lossless) = packLossy(signedCoefficientC, exponentC);
        // We don't care if power is lossy because it's an approximation anyway.
        (lossless);
        return c;
    }

    /// sqrt a = a ^ 0.5
    ///
    /// Due to the inaccuracies of log10 and power10, this is not perfectly
    /// accurate, a round trip like sqrt(x)^2 will typically be within half a
    /// percent or less of the original value, but this can vary depending on
    /// the input values.
    ///
    /// Doesn't lose precision due to the exponent, for a wide range of
    /// exponents.
    /// @param a The float to take the square root of.
    /// @param tablesDataContract The address of the contract containing the
    /// logarithm tables.
    function sqrt(Float a, address tablesDataContract) internal view returns (Float) {
        return pow(a, FLOAT_HALF, tablesDataContract);
    }

    /// Returns the minimum of two values.
    /// Convenience for `a < b ? a : b`.
    /// @param a The first float to compare.
    /// @param b The second float to compare.
    /// @return The minimum of the two floats.
    function min(Float a, Float b) internal pure returns (Float) {
        return lt(a, b) ? a : b;
    }

    /// Returns the maximum of two values.
    /// Convenience for `a > b ? a : b`.
    /// @param a The first float to compare.
    /// @param b The second float to compare.
    function max(Float a, Float b) internal pure returns (Float) {
        return gt(a, b) ? a : b;
    }

    function isZero(Float a) internal pure returns (bool result) {
        uint256 mask = type(uint224).max;
        assembly ("memory-safe") {
            // Don't need to signextend here because we only care if the value
            // is zero or not.
            result := iszero(and(a, mask))
        }
    }
}
