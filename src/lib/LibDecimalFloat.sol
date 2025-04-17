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
    Log10Negative,
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

uint256 constant ADD_MAX_EXPONENT_DIFF = 37;

/// @dev When normalizing a number, how far we "leap" when very far from
/// normalized.
int256 constant EXPONENT_LEAP_SIZE = 24;
/// @dev The multiplier for the leap size, calculated at compile time.
int256 constant EXPONENT_LEAP_MULTIPLIER = int256(uint256(10 ** uint256(EXPONENT_LEAP_SIZE)));

// /// @dev An in memory representation of a float. This is more gas intensive but
// /// helps mitigate stack depth issues, and is more ergonomic for the caller.
// /// This is not a packed representation, so it is not normalized.
// /// @param signedCoefficient The signed coefficient of the floating point
// /// representation.
// /// @param exponent The exponent of the floating point representation.
// struct Float {
//     int256 signedCoefficient;
//     int256 exponent;
// }

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
        return (pack(signedCoefficient, exponent), lossless);
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
        return pack(signedCoefficient, exponent);
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
    function pack(int256 signedCoefficient, int256 exponent) internal pure returns (Float float) {
        if (int224(signedCoefficient) != signedCoefficient) {
            revert CoefficientOverflow(signedCoefficient, exponent);
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

    /// Add two floats together as a normalized result.
    ///
    /// Note that because the input values can have arbitrary exponents that may
    /// be very far apart, the normalization process is necessarily lossy.
    /// For example, normalized 1 is 1e37 coefficient and -37 exponent.
    /// Consider adding 1e37 coefficient with exponent 1.
    /// These two numbers are identical in coefficient but their exponents are
    /// 38 OOMs apart. While we can perform the addition and get the correct
    /// result internally, as soon as we normalize the result, we will lose
    /// precision and the result will be 1e37 coefficient with -37 exponent.
    /// The precision of addition is therefore best case the full 37 decimals
    /// representable in normalized form, if the two numbers share the same
    /// exponent, but each step of exponent difference will lose a decimal of
    /// precision in the output. In practise, this rarely matters as the onchain
    /// conventions for amounts are typically 18 decimals or less, and so entire
    /// token supplies are typically representable within ~26-33 decimals of
    /// precision, making addition lossless for all actual possible values.
    ///
    /// https://speleotrove.com/decimal/daops.html#refaddsub
    /// > add and subtract both take two operands. If either operand is a special
    /// > value then the general rules apply.
    /// >
    /// > Otherwise, the operands are added (after inverting the sign used for
    /// > the second operand if the operation is a subtraction), as follows:
    /// >
    /// > The coefficient of the result is computed by adding or subtracting the
    /// > aligned coefficients of the two operands. The aligned coefficients are
    /// > computed by comparing the exponents of the operands:
    /// >
    /// > - If they have the same exponent, the aligned coefficients are the same
    /// > as the original coefficients.
    /// > - Otherwise the aligned coefficient of the number with the larger
    /// > exponent is its original coefficient multiplied by 10^n, where n is the
    /// > absolute difference between the exponents, and the aligned coefficient
    /// > of the other operand is the same as its original coefficient.
    /// >
    /// > If the signs of the operands differ then the smaller aligned
    /// > coefficient is subtracted from the larger; otherwise they are added.
    /// >
    /// > The exponent of the result is the minimum of the exponents of the two
    /// > operands.
    /// >
    /// > The sign of the result is determined as follows:
    /// >
    /// > - If the result is non-zero then the sign of the result is the sign of
    /// > the operand having the larger absolute value.
    /// > - Otherwise, the sign of a zero result is 0 unless either both operands
    /// > were negative or the signs of the operands were different and the
    /// > rounding is round-floor.
    ///
    /// @param signedCoefficientA The signed coefficient of the first floating
    /// point number.
    /// @param exponentA The exponent of the first floating point number.
    /// @param signedCoefficientB The signed coefficient of the second floating
    /// point number.
    /// @param exponentB The exponent of the second floating point number.
    /// @return signedCoefficient The signed coefficient of the result.
    /// @return exponent The exponent of the result.
    function add(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
        // Zero for either is the edge case but we have to guard against it.
        // Doing it eagerly with assembly is less gas than lazily with jumps.
        bool eitherZero;
        assembly ("memory-safe") {
            eitherZero := or(iszero(signedCoefficientA), iszero(signedCoefficientB))
        }
        if (eitherZero) {
            if (signedCoefficientA == 0) {
                return (signedCoefficientB, exponentB);
            } else {
                return (signedCoefficientA, exponentA);
            }
        }

        // Normalizing A and B gives us similar coefficients, which simplifies
        // detecting when their exponents are too far apart to add without
        // simply ignoring one of them.
        (signedCoefficientA, exponentA) = LibDecimalFloatImplementation.normalize(signedCoefficientA, exponentA);
        (signedCoefficientB, exponentB) = LibDecimalFloatImplementation.normalize(signedCoefficientB, exponentB);

        // We want A to represent the larger exponent. If this is not the case
        // then swap them.
        if (exponentB > exponentA) {
            int256 tmp = signedCoefficientA;
            signedCoefficientA = signedCoefficientB;
            signedCoefficientB = tmp;

            tmp = exponentA;
            exponentA = exponentB;
            exponentB = tmp;
        }

        // After normalization the signed coefficients are the same OOM in
        // magnitude. However, what we need is for the exponents to be the same.
        // If the exponents are close enough we can multiply coefficient A by
        // some power of 10 to align their exponents without precision loss.
        // If the exponents are too far apart, then all the information in B
        // would be lost by the final normalization step, so we can just ignore
        // B and return A.
        uint256 multiplier;
        unchecked {
            uint256 alignmentExponentDiff = uint256(exponentA - exponentB);
            // The early return here allows us to do unchecked pow on the
            // multiplier and means we never revert due to overflow here.
            if (alignmentExponentDiff > ADD_MAX_EXPONENT_DIFF) {
                return (signedCoefficientA, exponentA);
            }
            multiplier = 10 ** alignmentExponentDiff;
        }
        signedCoefficientA *= int256(multiplier);

        // The actual addition step.
        unchecked {
            signedCoefficientA += signedCoefficientB;
        }
        return (signedCoefficientA, exponentB);
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
        (int256 signedCoefficient, int256 exponent) = add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        return pack(signedCoefficient, exponent);
    }

    /// Subtract two floats together as a normalized result.
    ///
    /// This is effectively shorthand for adding the two floats with the second
    /// float negated. Therefore, the same caveats apply as for `add`.
    /// @param signedCoefficientA The signed coefficient of the first floating
    /// point number.
    /// @param exponentA The exponent of the first floating point number.
    /// @param signedCoefficientB The signed coefficient of the second floating
    /// point number.
    /// @param exponentB The exponent of the second floating point number.
    /// @return signedCoefficient The signed coefficient of the result.
    /// @return exponent The exponent of the result.
    function sub(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
        (signedCoefficientB, exponentB) = minus(signedCoefficientB, exponentB);
        return add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// Same as sub, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param a The Float struct containing the signed coefficient and
    /// exponent of the first floating point number.
    /// @param b The Float struct containing the signed coefficient and
    /// exponent of the second floating point number.
    function sub(Float a, Float b) internal pure returns (Float result) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (int256 signedCoefficient, int256 exponent) = sub(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        return pack(signedCoefficient, exponent);
    }

    /// Negates and normalizes a float.
    /// Equivalent to `0 - x`.
    ///
    /// https://speleotrove.com/decimal/daops.html#refplusmin
    /// > minus and plus both take one operand, and correspond to the prefix
    /// > minus and plus operators in programming languages.
    /// >
    /// > The operations are evaluated using the same rules as add and subtract;
    /// > the operations plus(a) and minus(a)
    /// > (where a and b refer to any numbers) are calculated as the operations
    /// > add(’0’, a) and subtract(’0’, b) respectively, where the ’0’ has the
    /// > same exponent as the operand.
    ///
    /// @param signedCoefficient The signed coefficient of the floating point
    /// number.
    /// @param exponent The exponent of the floating point number.
    /// @return signedCoefficient The signed coefficient of the result.
    /// @return exponent The exponent of the result.
    function minus(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        unchecked {
            // This is the only edge case that can't be simply negated.
            if (signedCoefficient == type(int256).min) {
                if (exponent == type(int256).max) {
                    revert ExponentOverflow(signedCoefficient, exponent);
                }
                signedCoefficient /= 10;
                ++exponent;
            }
            return (-signedCoefficient, exponent);
        }
    }

    /// Same as minus, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param float The Float struct containing the signed coefficient and
    /// exponent of the floating point number.
    function minus(Float float) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        (signedCoefficient, exponent) = minus(signedCoefficient, exponent);
        return pack(signedCoefficient, exponent);
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
    function abs(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        unchecked {
            if (signedCoefficient < 0) {
                return minus(signedCoefficient, exponent);
            }

            return (signedCoefficient, exponent);
        }
    }

    /// Same as abs, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param float The Float struct containing the signed coefficient and
    /// exponent of the floating point number.
    function abs(Float float) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        (signedCoefficient, exponent) = abs(signedCoefficient, exponent);
        return pack(signedCoefficient, exponent);
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
    function multiply(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
        unchecked {
            // Unchecked mul the coefficients and add the exponents.
            int256 signedCoefficient = signedCoefficientA * signedCoefficientB;

            // Need to return early if the result is zero to avoid divide by
            // zero in the overflow check.
            if (signedCoefficient == 0) {
                return (NORMALIZED_ZERO_SIGNED_COEFFICIENT, NORMALIZED_ZERO_EXPONENT);
            }

            int256 exponent = exponentA + exponentB;

            // No jumps to see if we overflowed.
            bool didOverflow;
            assembly ("memory-safe") {
                didOverflow :=
                    or(
                        iszero(eq(sdiv(signedCoefficient, signedCoefficientA), signedCoefficientB)),
                        iszero(eq(sub(exponent, exponentA), exponentB))
                    )
            }
            // If we did overflow, normalize and try again. Normalized values
            // cannot overflow, so this will always succeed, provided the
            // exponents are not out of bounds.
            if (didOverflow) {
                (signedCoefficientA, exponentA) = LibDecimalFloatImplementation.normalize(signedCoefficientA, exponentA);
                (signedCoefficientB, exponentB) = LibDecimalFloatImplementation.normalize(signedCoefficientB, exponentB);
                return multiply(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
            }
            return (signedCoefficient, exponent);
        }
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
            multiply(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        return pack(signedCoefficient, exponent);
    }

    /// https://speleotrove.com/decimal/daops.html#refdivide
    /// > divide takes two operands. If either operand is a special value then
    /// > the general rules apply.
    /// > Otherwise, if the divisor is zero then either the Division undefined
    /// > condition is raised (if the dividend is zero) and the result is NaN,
    /// > or the Division by zero condition is raised and the result is an
    /// > Infinity with a sign which is the exclusive or of the signs of the
    /// > operands.
    /// >
    /// > Otherwise, a ‘long division’ is effected, as follows:
    /// >
    /// > - An integer variable, adjust, is initialized to 0.
    /// > - If the dividend is non-zero, the coefficient of the result is
    /// >   computed as follows (using working copies of the operand
    /// >   coefficients, as necessary):
    /// >   - The operand coefficients are adjusted so that the coefficient of
    /// >     the dividend is greater than or equal to the coefficient of the
    /// >     divisor and is also less than ten times the coefficient of the
    /// >     divisor, thus:
    /// >     - While the coefficient of the dividend is less than the
    /// >       coefficient of the divisor it is multiplied by 10 and adjust is
    /// >       incremented by 1.
    /// >     - While the coefficient of the dividend is greater than or equal to
    /// >       ten times the coefficient of the divisor the coefficient of the
    /// >       divisor is multiplied by 10 and adjust is decremented by 1.
    /// >   - The result coefficient is initialized to 0.
    /// >   - The following steps are then repeated until the division is
    /// >     complete:
    /// >     - While the coefficient of the divisor is smaller than or equal to
    /// >       the coefficient of the dividend the former is subtracted from the
    /// >       latter and the coefficient of the result is incremented by 1.
    /// >     - If the coefficient of the dividend is now 0 and adjust is greater
    /// >       than or equal to 0, or if the coefficient of the result has
    /// >       precision digits, the division is complete. Otherwise, the
    /// >       coefficients of the result and the dividend are multiplied by 10
    /// >       and adjust is incremented by 1.
    /// >   - Any remainder (the final coefficient of the dividend) is recorded
    /// >     and taken into account for rounding.[3]
    /// >   Otherwise (the dividend is zero), the coefficient of the result is
    /// >   zero and adjust is unchanged (is 0).
    /// > - The exponent of the result is computed by subtracting the sum of the
    /// >   original exponent of the divisor and the value of adjust at the end
    /// >   of the coefficient calculation from the original exponent of the
    /// >   dividend.
    /// > - The sign of the result is the exclusive or of the signs of the
    /// >   operands.
    /// >
    /// > The result is then rounded to precision digits, if necessary, according
    /// > to the rounding algorithm and taking into account the remainder from
    /// > the division.
    function divide(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
        unchecked {
            (signedCoefficientA, exponentA) = LibDecimalFloatImplementation.normalize(signedCoefficientA, exponentA);
            (signedCoefficientB, exponentB) = LibDecimalFloatImplementation.normalize(signedCoefficientB, exponentB);

            int256 signedCoefficient = (signedCoefficientA * 1e38) / signedCoefficientB;
            int256 exponent = exponentA - exponentB - 38;
            return (signedCoefficient, exponent);
        }
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
            divide(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        return pack(signedCoefficient, exponent);
    }

    /// Inverts a float. Equivalent to `1 / x` with modest gas optimizations.
    function inv(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.normalize(signedCoefficient, exponent);

        signedCoefficient = 1e75 / signedCoefficient;
        exponent = -exponent - 75;

        return (signedCoefficient, exponent);
    }

    /// Same as inv, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param float The Float struct containing the signed coefficient and
    /// exponent of the floating point number.
    function inv(Float float) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        (signedCoefficient, exponent) = inv(signedCoefficient, exponent);
        return pack(signedCoefficient, exponent);
    }

    /// Numeric equality for floats.
    /// Two floats are equal if their numeric value is equal.
    /// For example, 1e2, 10e1, and 100e0 are all equal. Also implies that 0eX
    /// and 0eY are equal for all X and Y.
    /// Any representable value can be equality checked without precision loss,
    /// e.g. no normalization is done internally.
    /// @param signedCoefficientA The signed coefficient of the first floating
    /// point number.
    /// @param exponentA The exponent of the first floating point number.
    /// @param signedCoefficientB The signed coefficient of the second floating
    /// point number.
    /// @param exponentB The exponent of the second floating point number.
    /// @return `true` if the two floats are equal, `false` otherwise.
    function eq(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (bool)
    {
        (signedCoefficientA, signedCoefficientB) =
            LibDecimalFloatImplementation.compareRescale(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        return signedCoefficientA == signedCoefficientB;
    }

    /// Same as eq, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param a The Float struct containing the signed coefficient and
    /// exponent of the first floating point number.
    /// @param b The Float struct containing the signed coefficient and
    /// exponent of the second floating point number.
    function eq(Float a, Float b) internal pure returns (bool) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        return eq(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// Numeric less than for floats.
    /// A float is less than another if its numeric value is less than the other.
    /// For example, 1e2 is less than 1e3, and 1e2 is less than 2e2.
    /// Any representable value can be compared without precision loss, e.g. no
    /// normalization is done internally.
    /// @param signedCoefficientA The signed coefficient of the first floating
    /// point number.
    /// @param exponentA The exponent of the first floating point number.
    /// @param signedCoefficientB The signed coefficient of the second floating
    /// point number.
    /// @param exponentB The exponent of the second floating point number.
    /// @return `true` if the first float is less than the second, `false`
    /// otherwise.
    function lt(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (bool)
    {
        (signedCoefficientA, signedCoefficientB) =
            LibDecimalFloatImplementation.compareRescale(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        return signedCoefficientA < signedCoefficientB;
    }

    /// Same as lt, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param a The Float struct containing the signed coefficient and
    /// exponent of the first floating point number.
    /// @param b The Float struct containing the signed coefficient and
    /// exponent of the second floating point number.
    function lt(Float a, Float b) internal pure returns (bool) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        return lt(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// Numeric greater than for floats.
    /// A float is greater than another if its numeric value is greater than the
    /// other. For example, 1e3 is greater than 1e2, and 2e2 is greater than 1e2.
    /// Any representable value can be compared without precision loss, e.g. no
    /// normalization is done internally.
    /// @param signedCoefficientA The signed coefficient of the first floating
    /// point number.
    /// @param exponentA The exponent of the first floating point number.
    /// @param signedCoefficientB The signed coefficient of the second floating
    /// point number.
    /// @param exponentB The exponent of the second floating point number.
    /// @return `true` if the first float is greater than the second, `false`
    /// otherwise.
    function gt(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (bool)
    {
        (signedCoefficientA, signedCoefficientB) =
            LibDecimalFloatImplementation.compareRescale(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        return signedCoefficientA > signedCoefficientB;
    }

    /// Same as gt, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param a The Float struct containing the signed coefficient and
    /// exponent of the first floating point number.
    /// @param b The Float struct containing the signed coefficient and
    /// exponent of the second floating point number.
    function gt(Float a, Float b) internal pure returns (bool) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        return gt(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// Fractional component of a float.
    /// @param signedCoefficient The signed coefficient of the floating point
    /// number.
    /// @param exponent The exponent of the floating point number.
    /// @return signedCoefficient The signed coefficient of the fractional
    /// component.
    /// @return exponent The exponent of the fractional component.
    function frac(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        (int256 characteristic, int256 mantissa) =
            LibDecimalFloatImplementation.characteristicMantissa(signedCoefficient, exponent);
        (characteristic);
        return (mantissa, exponent);
    }

    /// Same as frac, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param float The Float struct containing the signed coefficient and
    /// exponent of the floating point number.
    function frac(Float float) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        (signedCoefficient, exponent) = frac(signedCoefficient, exponent);
        return pack(signedCoefficient, exponent);
    }

    /// Integer component of a float.
    /// @param signedCoefficient The signed coefficient of the floating point
    /// number.
    /// @param exponent The exponent of the floating point number.
    /// @return signedCoefficient The signed coefficient of the integer
    /// component.
    /// @return exponent The exponent of the integer component.
    function floor(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        (int256 characteristic, int256 mantissa) =
            LibDecimalFloatImplementation.characteristicMantissa(signedCoefficient, exponent);
        (mantissa);
        return (characteristic, exponent);
    }

    /// Same as floor, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param float The Float struct containing the signed coefficient and
    /// exponent of the floating point number.
    function floor(Float float) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        (signedCoefficient, exponent) = floor(signedCoefficient, exponent);
        return pack(signedCoefficient, exponent);
    }

    /// 10^x for a float x.
    ///
    /// Internally uses log tables so is not perfectly accurate, but also doesn't
    /// require any loops or iterations, and works across a wide range of
    /// exponents without precision loss.
    ///
    /// @param signedCoefficient The signed coefficient of the floating point
    /// number.
    /// @param exponent The exponent of the floating point number.
    /// @return signedCoefficient The signed coefficient of the result.
    /// @return exponent The exponent of the result.
    function power10(address tablesDataContract, int256 signedCoefficient, int256 exponent)
        internal
        view
        returns (int256, int256)
    {
        unchecked {
            if (signedCoefficient < 0) {
                (signedCoefficient, exponent) = minus(signedCoefficient, exponent);
                (signedCoefficient, exponent) = power10(tablesDataContract, signedCoefficient, exponent);
                return inv(signedCoefficient, exponent);
            }

            // Table lookup.
            (int256 characteristicCoefficient, int256 mantissaCoefficient) =
                LibDecimalFloatImplementation.characteristicMantissa(signedCoefficient, exponent);
            int256 characteristicExponent = exponent;
            {
                (int256 idx, bool interpolate) = LibDecimalFloatImplementation.mantissa4(mantissaCoefficient, exponent);
                (int256 y1Coefficient, int256 y2Coefficient) =
                    LibDecimalFloatImplementation.lookupAntilogTableY1Y2(tablesDataContract, uint256(idx), interpolate);

                if (interpolate) {
                    (signedCoefficient, exponent) = LibDecimalFloatImplementation.unitLinearInterpolation(
                        mantissaCoefficient, exponent, idx, -4, -41, y1Coefficient, y2Coefficient, -4
                    );
                } else {
                    signedCoefficient = y1Coefficient;
                    exponent = -4;
                }
            }

            return (
                signedCoefficient,
                1 + exponent
                    + LibDecimalFloatImplementation.withTargetExponent(characteristicCoefficient, characteristicExponent, 0)
            );
        }
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
        (signedCoefficient, exponent) = power10(tablesDataContract, signedCoefficient, exponent);
        return pack(signedCoefficient, exponent);
    }

    /// log10(x) for a float x.
    ///
    /// Internally uses log tables so is not perfectly accurate, but also doesn't
    /// require any loops or iterations, and works across a wide range of
    /// exponents without precision loss.
    ///
    /// @param signedCoefficient The signed coefficient of the floating point
    /// number.
    /// @param exponent The exponent of the floating point number.
    /// @return signedCoefficient The signed coefficient of the result.
    /// @return exponent The exponent of the result.
    function log10(address tablesDataContract, int256 signedCoefficient, int256 exponent)
        internal
        view
        returns (int256, int256)
    {
        unchecked {
            {
                (signedCoefficient, exponent) = LibDecimalFloatImplementation.normalize(signedCoefficient, exponent);

                if (signedCoefficient <= 0) {
                    if (signedCoefficient == 0) {
                        revert Log10Zero();
                    } else {
                        revert Log10Negative(signedCoefficient, exponent);
                    }
                }
            }

            // This is a positive log. i.e. log(x) where x >= 1.
            if (exponent > -38) {
                // This is an exact power of 10.
                if (signedCoefficient == 1e37) {
                    return (exponent + 37, 0);
                }

                int256 y1Coefficient;
                int256 y2Coefficient;
                int256 x1Coefficient;
                int256 x1Exponent = exponent;
                bool interpolate;

                // Table lookup.
                {
                    uint256 scale = 1e34;
                    assembly ("memory-safe") {
                        //slither-disable-next-line divide-before-multiply
                        function lookupTableVal(tables, index) -> result {
                            // First byte of the data contract must be skipped.
                            let mainOffset := add(1, mul(div(index, 10), 2))
                            mstore(0, 0)
                            extcodecopy(tables, 30, mainOffset, 2)
                            let mainTableVal := mload(0)

                            result := and(mainTableVal, 0x7FFF)
                            // Skip first byte of data contract then 1800 bytes
                            // of the log tables.
                            let smallTableOffset := 1801
                            if iszero(iszero(and(mainTableVal, 0x8000))) {
                                // Small table is half the size of the main
                                // table.
                                smallTableOffset := add(smallTableOffset, 900)
                            }

                            mstore(0, 0)
                            extcodecopy(
                                tables, 31, add(smallTableOffset, add(mul(div(index, 100), 10), mod(index, 10))), 1
                            )
                            result := add(result, mload(0))
                        }

                        // Truncate the signed coefficient to what we can look
                        // up in the table.
                        // Slither false positive because the truncation is
                        // deliberate here.
                        //slither-disable-next-line divide-before-multiply
                        x1Coefficient := div(signedCoefficient, scale)
                        let index := sub(x1Coefficient, 1000)
                        x1Coefficient := mul(x1Coefficient, scale)
                        interpolate := iszero(eq(x1Coefficient, signedCoefficient))

                        y1Coefficient := mul(scale, lookupTableVal(tablesDataContract, index))

                        if interpolate {
                            y2Coefficient := mul(scale, lookupTableVal(tablesDataContract, add(index, 1)))
                        }
                    }
                }

                if (interpolate) {
                    (signedCoefficient, exponent) = LibDecimalFloatImplementation.unitLinearInterpolation(
                        signedCoefficient, exponent, x1Coefficient, exponent, -39, y1Coefficient, y2Coefficient, -38
                    );
                } else {
                    signedCoefficient = y1Coefficient;
                    exponent = -38;
                }

                return add(signedCoefficient, exponent, x1Exponent + 37, 0);
            }
            // This is a negative log. i.e. log(x) where 0 < x < 1.
            // log(x) = -log(1/x)
            else {
                (signedCoefficient, exponent) = divide(1e37, -37, signedCoefficient, exponent);
                (signedCoefficient, exponent) = log10(tablesDataContract, signedCoefficient, exponent);
                return minus(signedCoefficient, exponent);
            }
        }
    }

    /// Same as log10, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param tablesDataContract The address of the contract containing the
    /// logarithm tables.
    /// @param float The Float struct containing the signed coefficient and
    /// exponent of the floating point number.
    function log10(address tablesDataContract, Float float) internal view returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        (signedCoefficient, exponent) = log10(tablesDataContract, signedCoefficient, exponent);
        return pack(signedCoefficient, exponent);
    }

    /// x^y = 10^(y * log10(x))
    ///
    /// Due to the inaccuraces of log10 and power10, this is not perfectly
    /// accurate, a round trip like x^y^(1/y) will typically be within half a
    /// percent or less of the original value, but this can vary depending on
    /// the input values.
    ///
    /// Doesn't lose precision due to the exponent, for a wide range of
    /// exponents.
    ///
    /// @param signedCoefficientA The signed coefficient of the base.
    /// @param exponentA The exponent of the base.
    /// @param signedCoefficientB The signed coefficient of the exponent.
    /// @param exponentB The exponent of the exponent.
    /// @return signedCoefficient The signed coefficient of the result.
    /// @return exponent The exponent of the result.
    function power(
        address tablesDataContract,
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) internal view returns (int256, int256) {
        (int256 signedCoefficient, int256 exponent) = log10(tablesDataContract, signedCoefficientA, exponentA);
        (signedCoefficient, exponent) = multiply(signedCoefficient, exponent, signedCoefficientB, exponentB);
        return power10(tablesDataContract, signedCoefficient, exponent);
    }

    /// Same as power, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param tablesDataContract The address of the contract containing the
    /// logarithm tables.
    /// @param a The Float struct containing the signed coefficient and
    /// exponent of the base.
    /// @param b The Float struct containing the signed coefficient and
    /// exponent of the exponent.
    function power(address tablesDataContract, Float a, Float b) internal view returns (Float) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (int256 signedCoefficient, int256 exponent) =
            power(tablesDataContract, signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        return pack(signedCoefficient, exponent);
    }

    /// Returns the minimum of two values.
    /// Convenience for `a < b ? a : b`.
    /// @param signedCoefficientA The signed coefficient of the first floating
    /// point number.
    /// @param exponentA The exponent of the first floating point number.
    /// @param signedCoefficientB The signed coefficient of the second floating
    /// point number.
    /// @param exponentB The exponent of the second floating point number.
    /// @return signedCoefficient The signed coefficient of the minimum value.
    /// @return exponent The exponent of the minimum value.
    function min(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
        if (lt(signedCoefficientA, exponentA, signedCoefficientB, exponentB)) {
            return (signedCoefficientA, exponentA);
        } else {
            return (signedCoefficientB, exponentB);
        }
    }

    /// Same as min, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param a The Float struct containing the signed coefficient and
    /// exponent of the first floating point number.
    /// @param b The Float struct containing the signed coefficient and
    /// exponent of the second floating point number.
    function min(Float a, Float b) internal pure returns (Float) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (int256 signedCoefficient, int256 exponent) = min(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        return pack(signedCoefficient, exponent);
    }

    /// Returns the maximum of two values.
    /// Convenience for `a > b ? a : b`.
    /// @param signedCoefficientA The signed coefficient of the first floating
    /// point number.
    /// @param exponentA The exponent of the first floating point number.
    /// @param signedCoefficientB The signed coefficient of the second floating
    /// point number.
    /// @param exponentB The exponent of the second floating point number.
    /// @return signedCoefficient The signed coefficient of the maximum value.
    /// @return exponent The exponent of the maximum value.
    function max(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
        if (gt(signedCoefficientA, exponentA, signedCoefficientB, exponentB)) {
            return (signedCoefficientA, exponentA);
        } else {
            return (signedCoefficientB, exponentB);
        }
    }

    /// Same as max, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param a The Float struct containing the signed coefficient and
    /// exponent of the first floating point number.
    /// @param b The Float struct containing the signed coefficient and
    /// exponent of the second floating point number.
    function max(Float a, Float b) internal pure returns (Float result) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (int256 signedCoefficient, int256 exponent) = max(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        return pack(signedCoefficient, exponent);
    }

    /// Same as normalize, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param float The Float struct containing the signed coefficient and
    /// exponent of the floating point number.
    function normalize(Float float) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        (int256 signedCoefficientNormalized, int256 exponentNormalized) =
            LibDecimalFloatImplementation.normalize(signedCoefficient, exponent);
        return pack(signedCoefficientNormalized, exponentNormalized);
    }
}
