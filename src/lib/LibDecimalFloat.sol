// SPDX-License-Identifier: CAL
pragma solidity ^0.8.25;

import {
    LOG_TABLES,
    LOG_TABLES_SMALL,
    LOG_TABLES_SMALL_ALT,
    ANTI_LOG_TABLES,
    ANTI_LOG_TABLES_SMALL
} from "../generated/LogTables.pointers.sol";
import {
    ExponentOverflow,
    CoefficientOverflow,
    Log10Zero,
    NegativeFixedDecimalConversion,
    LossyConversionFromFloat,
    LossyConversionToFloat
} from "../error/ErrDecimalFloat.sol";
import {
    LibDecimalFloatImplementation,
    NORMALIZED_ZERO_SIGNED_COEFFICIENT,
    NORMALIZED_ZERO_EXPONENT,
    NORMALIZED_MIN,
    NORMALIZED_MAX,
    EXPONENT_STEP_SIZE,
    SIGNED_NORMALIZED_MAX,
    EXPONENT_MAX,
    EXPONENT_MIN
} from "./implementation/LibDecimalFloatImplementation.sol";

type Float is bytes32;

/// @dev When normalizing a number, how far we "leap" when very far from
/// normalized.
int256 constant EXPONENT_LEAP_SIZE = 24;
/// @dev The multiplier for the leap size, calculated at compile time.
int256 constant EXPONENT_LEAP_MULTIPLIER = int256(uint256(10 ** uint256(EXPONENT_LEAP_SIZE)));

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
/// values as understood by humans. However, consider that we have 127 bits of
/// precision in the coefficient, which is far more than the 53 bits of a double
/// precision floating point number regardless of binary/decimal considerations,
/// and should be more than enough for most defi use cases.
///
/// A typical defi fixed point value has 18 decimals, while a normalized decimal
/// float in this system has 37 decimals. This means, for example, that we can
/// represent the entire supply of any 18 decimal fixed point token amount up to
/// 10 quintillion tokens, without any loss of precision.
///
/// One use case for this number system is representing ratios of tokens that
/// have both large differences in their decimals and unit value. For example,
/// at the time of writing, 1 SHIB is worth about 2.7e-10 BTC while the
/// WTBC contract only supports 8 decimals vs. SHIB's 18 decimals. It's literally
/// not possible to represent a purchase of 1 SHIB (1e18) worth of WBTC, so it's
/// easy to see how a fixed point decimal system could accidentally round
/// something down to `0` or up to `1` or similarly bad precision loss, simply
/// due to the large difference in OOMs in _representation_ of any two tokens
/// being considered.
///
/// Of course there are workarounds, such as temporarily inflating values during
/// calculations and rescaling them afterwards, but they are ad-hoc and error
/// prone. Importantly, the workarounds are typically not obvious to the target
/// demographic of Rainlang, and it is not obvious where/when they need to be
/// applied without rigourous testing/mathematical models that are beyond the
/// scope of the typical user of Rainlang.
library LibDecimalFloat {
    using LibDecimalFloat for Float;

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
                return (int256(value / 10), exponent + 1, value % 10 == 0);
            } else {
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
                    scale = 10 ** uint256(-finalExponent);
                    fixedDecimal = unsignedCoefficient / scale;

                    // Slither false positive because we're explicitly checking
                    // for the lossiness that it warns about.
                    //slither-disable-next-line divide-before-multiply
                    return (fixedDecimal, fixedDecimal * scale == unsignedCoefficient);
                }
            } else if (finalExponent > 0) {
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
    /// Normalized numbers are guaranteed to round trip through pack/unpack in
    /// a lossless manner. The normalization process will _truncate_ on precision
    /// loss if required, which is significantly better than potentially
    /// _decapitating_ a non-normalized number during the pack operation. It is
    /// highly recomended to normalize numbers before packing them.
    /// Note that mathematical operations in this lib all output normalized
    /// so typically this is implicit.
    /// @param signedCoefficient The signed coefficient of the floating point
    /// representation.
    /// @param exponent The exponent of the floating point representation.
    /// @return float The packed representation of the signed coefficient and
    /// exponent.
    function packLossy(int256 signedCoefficient, int256 exponent) internal pure returns (Float float, bool lossless) {
        unchecked {
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

                while (int224(signedCoefficient) != signedCoefficient) {
                    signedCoefficient /= 10;
                    ++exponent;
                }
            }

            if (int32(exponent) != exponent) {
                revert ExponentOverflow(signedCoefficient, exponent);
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
    /// the inverse of `pack`. Note that the unpacked values are not necessarily
    /// normalized, especially if their provenance is unknown or user input.
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

    /// Subtract two floats together as a normalized result.
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

    /// Same as multiply, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param a The Float struct containing the signed coefficient and
    /// exponent of the first floating point number.
    /// @param b The Float struct containing the signed coefficient and
    /// exponent of the second floating point number.
    function multiply(Float a, Float b) internal pure returns (Float) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.multiply(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
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
    function divide(Float a, Float b) internal pure returns (Float) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.divide(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
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
        // Inversion cannot be lossy as long as the denominator is normalized.
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
    /// Any representable value can be compared without precision loss, e.g. no
    /// normalization is done internally.
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
    /// Any representable value can be compared without precision loss, e.g. no
    /// normalization is done internally.
    /// @param a The first float to compare.
    /// @param b The second float to compare.
    function gt(Float a, Float b) internal pure returns (bool) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (signedCoefficientA, signedCoefficientB) =
            LibDecimalFloatImplementation.compareRescale(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        return signedCoefficientA > signedCoefficientB;
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
        (int256 characteristic, int256 mantissa) =
            LibDecimalFloatImplementation.characteristicMantissa(signedCoefficient, exponent);
        (Float result, bool lossless) = packLossy(characteristic, exponent);
        // Flooring is lossy by definition.
        (lossless, mantissa);
        return result;
    }

    /// Same as power10, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param tablesDataContract The address of the contract containing the
    /// logarithm tables.
    /// @param float The Float struct containing the signed coefficient and
    /// exponent of the floating point number.
    function power10(address tablesDataContract, Float float) internal view returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        (signedCoefficient, exponent) =
            LibDecimalFloatImplementation.power10(tablesDataContract, signedCoefficient, exponent);
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
    function power(Float a, Float b, address tablesDataContract) internal view returns (Float) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientC, int256 exponentC) =
            LibDecimalFloatImplementation.log10(tablesDataContract, signedCoefficientA, exponentA);
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (signedCoefficientC, exponentC) =
            LibDecimalFloatImplementation.multiply(signedCoefficientC, exponentC, signedCoefficientB, exponentB);
        (signedCoefficientC, exponentC) =
            LibDecimalFloatImplementation.power10(tablesDataContract, signedCoefficientC, exponentC);
        (Float c, bool lossless) = packLossy(signedCoefficientC, exponentC);
        // We don't care if power is lossy because it's an approximation anyway.
        (lossless);
        return c;
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
}
