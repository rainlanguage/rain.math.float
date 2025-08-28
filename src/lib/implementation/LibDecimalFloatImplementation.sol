// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {ExponentOverflow, Log10Negative, Log10Zero, MulDivOverflow} from "../../error/ErrDecimalFloat.sol";
import {
    LOG_TABLES,
    LOG_TABLES_SMALL,
    LOG_TABLES_SMALL_ALT,
    ANTI_LOG_TABLES,
    ANTI_LOG_TABLES_SMALL
} from "../../generated/LogTables.pointers.sol";
import {LibDecimalFloat} from "../LibDecimalFloat.sol";

error WithTargetExponentOverflow(int256 signedCoefficient, int256 exponent, int256 targetExponent);

uint256 constant ADD_MAX_EXPONENT_DIFF = 76;

/// @dev The maximum exponent that can be normalized.
/// This is crazy large, so should never be a problem for any real use case.
/// We need it to guard against overflow when normalizing.
int256 constant EXPONENT_MAX = type(int256).max / 2;
int256 constant EXPONENT_MAX_PLUS_ONE = EXPONENT_MAX + 1;

/// @dev The minimum exponent that can be normalized.
/// This is crazy small, so should never be a problem for any real use case.
/// We need it to guard against overflow when normalizing.
int256 constant EXPONENT_MIN = -EXPONENT_MAX;

/// @dev When normalizing a number, how far we "step" when close to normalized.
int256 constant EXPONENT_STEP_SIZE = 1;
/// @dev The multiplier for the step size, calculated at compile time.
int256 constant EXPONENT_STEP_MULTIPLIER = int256(uint256(10 ** uint256(EXPONENT_STEP_SIZE)));
/// @dev When normalizing a number, how far we "jump" when somewhat far from
/// normalized.
int256 constant EXPONENT_JUMP_SIZE = 6;
/// @dev The multiplier for the jump size, calculated at compile time.
int256 constant PRECISION_JUMP_MULTIPLIER = int256(uint256(10 ** uint256(EXPONENT_JUMP_SIZE)));
/// @dev Every value above or equal to this can jump down while normalizing
/// without overshooting and causing unnecessary precision loss.
int256 constant NORMALIZED_JUMP_DOWN_THRESHOLD = SIGNED_NORMALIZED_MAX * PRECISION_JUMP_MULTIPLIER;
/// @dev Every value below this can jump up while normalizing without
/// overshooting the normalized range.
int256 constant NORMALIZED_JUMP_UP_THRESHOLD = SIGNED_NORMALIZED_MIN / PRECISION_JUMP_MULTIPLIER;

/// @dev The minimum absolute value of a normalized signed coefficient.
uint256 constant NORMALIZED_MIN = 1e37;
int256 constant SIGNED_NORMALIZED_MIN = 1e37;
/// @dev The maximum absolute value of a normalized signed coefficient.
uint256 constant NORMALIZED_MAX = 1e38 - 1;
int256 constant SIGNED_NORMALIZED_MAX = 1e38 - 1;
uint256 constant NORMALIZED_MAX_PLUS_ONE = 1e38;
int256 constant SIGNED_NORMALIZED_MAX_PLUS_ONE = 1e38;

/// @dev The signed coefficient of maximized zero.
int256 constant MAXIMIZED_ZERO_SIGNED_COEFFICIENT = 0;
/// @dev The exponent of maximized zero.
int256 constant MAXIMIZED_ZERO_EXPONENT = 0;

library LibDecimalFloatImplementation {
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

    function absUnsignedSignedCoefficient(int256 signedCoefficient) internal pure returns (uint256) {
        unchecked {
            if (signedCoefficient < 0) {
                if (signedCoefficient == type(int256).min) {
                    return uint256(type(int256).max) + 1;
                } else {
                    return uint256(-signedCoefficient);
                }
            } else {
                return uint256(signedCoefficient);
            }
        }
    }

    function unabsUnsignedMulOrDivLossy(int256 a, int256 b, uint256 signedCoefficientAbs, int256 exponent)
        internal
        pure
        returns (int256, int256)
    {
        unchecked {
            // Need to minus the coefficient because a and b had different signs.
            if ((a ^ b) < 0) {
                if (signedCoefficientAbs > uint256(type(int256).max)) {
                    if (signedCoefficientAbs == uint256(type(int256).max) + 1) {
                        // Edge case where the absolute value is exactly
                        // type(int256).min.
                        return (type(int256).min, exponent);
                    } else {
                        return (-int256(signedCoefficientAbs / 10), exponent + 1);
                    }
                } else {
                    return (-int256(signedCoefficientAbs), exponent);
                }
            } else {
                if (signedCoefficientAbs > uint256(type(int256).max)) {
                    return (int256(signedCoefficientAbs / 10), exponent + 1);
                } else {
                    return (int256(signedCoefficientAbs), exponent);
                }
            }
        }
    }

    /// Stack only implementation of `mul`.
    function mul(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256 signedCoefficient, int256 exponent)
    {
        bool isZero;
        assembly ("memory-safe") {
            isZero := or(iszero(signedCoefficientA), iszero(signedCoefficientB))
        }
        if (isZero) {
            // These sets are redundant as both are zero but this makes it
            // clearer and more explicit.
            signedCoefficient = MAXIMIZED_ZERO_SIGNED_COEFFICIENT;
            exponent = MAXIMIZED_ZERO_EXPONENT;
        } else {
            exponent = exponentA + exponentB;

            // mulDiv only works with unsigned integers, so get the absolute
            // values of the coefficients.
            uint256 signedCoefficientAAbs = absUnsignedSignedCoefficient(signedCoefficientA);
            uint256 signedCoefficientBAbs = absUnsignedSignedCoefficient(signedCoefficientB);

            (uint256 prod1,) = mul512(signedCoefficientAAbs, signedCoefficientBAbs);

            uint256 adjustExponent = 0;
            unchecked {
                if (prod1 > 1e37) {
                    prod1 /= 1e37;
                    adjustExponent += 37;
                }
                if (prod1 > 1e18) {
                    prod1 /= 1e18;
                    adjustExponent += 18;
                }
                if (prod1 > 1e9) {
                    prod1 /= 1e9;
                    adjustExponent += 9;
                }
                if (prod1 > 1e4) {
                    prod1 /= 1e4;
                    adjustExponent += 4;
                }
                while (prod1 > 0) {
                    prod1 /= 10;
                    adjustExponent++;
                }
            }

            exponent += int256(adjustExponent);

            (signedCoefficient, exponent) = unabsUnsignedMulOrDivLossy(
                signedCoefficientA,
                signedCoefficientB,
                mulDiv(signedCoefficientAAbs, signedCoefficientBAbs, uint256(10) ** adjustExponent),
                exponent
            );
        }
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
    function div(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256 signedCoefficient, int256 exponent)
    {
        if (signedCoefficientA == 0) {
            signedCoefficient = MAXIMIZED_ZERO_SIGNED_COEFFICIENT;
            exponent = MAXIMIZED_ZERO_EXPONENT;
        } else {
            // Move both coefficients into the e75/e76 range, so that the result
            // of division will not cause a mulDiv overflow.
            (signedCoefficientA, exponentA) = maximize(signedCoefficientA, exponentA);
            (signedCoefficientB, exponentB) = maximize(signedCoefficientB, exponentB);

            // mulDiv only works with unsigned integers, so get the absolute
            // values of the coefficients.
            uint256 signedCoefficientAAbs = absUnsignedSignedCoefficient(signedCoefficientA);
            uint256 signedCoefficientBAbs = absUnsignedSignedCoefficient(signedCoefficientB);

            uint256 scale = 1e76;
            int256 adjustExponent = 76;

            // We are going to scale the numerator up by the largest power of ten
            // that is smaller than the denominator. This will always overflow
            // internally to the mulDiv during the initial multiplication, in
            // 512 bits, but will subsequently always be reduced back down to
            // fit in 256 bits by the division of a denominator that is larger
            // than the scale up.
            if (signedCoefficientBAbs < scale) {
                scale = 1e75;
                adjustExponent = 75;
            }
            // The order of subtraction matters in edge cases. For non-negative
            // exponentA, apply the adjust exponent first to move the value
            // towards 0 before exponentB is applied. This reduces the chance of
            // a transient overflow in the intermediate subtraction.
            if (exponentA >= 0) {
                exponent = exponentA - adjustExponent - exponentB;
            } else {
                exponent = exponentA - exponentB - adjustExponent;
            }

            (signedCoefficient, exponent) = unabsUnsignedMulOrDivLossy(
                signedCoefficientA,
                signedCoefficientB,
                mulDiv(signedCoefficientAAbs, scale, signedCoefficientBAbs),
                exponent
            );
        }
    }

    /// mul512 from Open Zeppelin.
    /// Simply part of the original mulDiv function abstracted out for reuse
    /// elsewhere.
    function mul512(uint256 a, uint256 b) internal pure returns (uint256 high, uint256 low) {
        // 512-bit multiply [high low] = x * y. Compute the product mod 2²⁵⁶ and mod 2²⁵⁶ - 1, then use
        // the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
        // variables such that product = high * 2²⁵⁶ + low.
        assembly ("memory-safe") {
            let mm := mulmod(a, b, not(0))
            low := mul(a, b)
            high := sub(sub(mm, low), lt(mm, low))
        }
    }

    /// mulDiv as seen in Open Zeppelin, PRB Math, Solady, and other libraries.
    /// Credit to Remco Bloemen under MIT license: https://2π.com/21/muldiv
    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        (uint256 prod1, uint256 prod0) = mul512(x, y);

        // Handle non-overflow cases, 256 by 256 division.
        if (prod1 == 0) {
            unchecked {
                return prod0 / denominator;
            }
        }

        // Make sure the result is less than 2^256. Also prevents denominator == 0.
        if (prod1 >= denominator) {
            revert MulDivOverflow(x, y, denominator);
        }

        ////////////////////////////////////////////////////////////////////////////
        // 512 by 256 division
        ////////////////////////////////////////////////////////////////////////////

        // Make division exact by subtracting the remainder from [prod1 prod0].
        uint256 remainder;
        assembly ("memory-safe") {
            // Compute remainder using the mulmod Yul instruction.
            remainder := mulmod(x, y, denominator)

            // Subtract 256 bit number from 512-bit number.
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        unchecked {
            // Calculate the largest power of two divisor of the denominator using the unary operator ~. This operation cannot overflow
            // because the denominator cannot be zero at this point in the function execution. The result is always >= 1.
            // For more detail, see https://cs.stackexchange.com/q/138556/92363.
            uint256 lpotdod = denominator & (~denominator + 1);
            uint256 flippedLpotdod;

            assembly ("memory-safe") {
                // Factor powers of two out of denominator.
                // slither-disable-next-line divide-before-multiply
                denominator := div(denominator, lpotdod)

                // Divide [prod1 prod0] by lpotdod.
                // slither-disable-next-line divide-before-multiply
                prod0 := div(prod0, lpotdod)

                // Get the flipped value `2^256 / lpotdod`. If the `lpotdod` is zero, the flipped value is one.
                // `sub(0, lpotdod)` produces the two's complement version of `lpotdod`, which is equivalent to flipping all the bits.
                // However, `div` interprets this value as an unsigned value: https://ethereum.stackexchange.com/q/147168/24693
                flippedLpotdod := add(div(sub(0, lpotdod), lpotdod), 1)
            }

            // Shift in bits from prod1 into prod0.
            prod0 |= prod1 * flippedLpotdod;

            // Invert denominator mod 2^256. Now that denominator is an odd number, it has an inverse modulo 2^256 such
            // that denominator * inv = 1 mod 2^256. Compute the inverse by starting with a seed that is correct for
            // four bits. That is, denominator * inv = 1 mod 2^4.
            // slither-disable-next-line incorrect-exp
            uint256 inverse = (3 * denominator) ^ 2;

            // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also works
            // in modular arithmetic, doubling the correct bits in each step.
            inverse *= 2 - denominator * inverse; // inverse mod 2^8
            inverse *= 2 - denominator * inverse; // inverse mod 2^16
            inverse *= 2 - denominator * inverse; // inverse mod 2^32
            inverse *= 2 - denominator * inverse; // inverse mod 2^64
            inverse *= 2 - denominator * inverse; // inverse mod 2^128
            inverse *= 2 - denominator * inverse; // inverse mod 2^256

            // Because the division is now exact we can divide by multiplying with the modular inverse of denominator.
            // This will give us the correct result modulo 2^256. Since the preconditions guarantee that the outcome is
            // less than 2^256, this is the final result. We don't need to compute the high bits of the result and prod1
            // is no longer required.
            result = prod0 * inverse;
        }
    }

    /// Add two floats together.
    ///
    /// Note that because the input values can have arbitrary exponents that may
    /// be very far apart, the addition process is necessarily lossy.
    /// Consider adding 1e100 to 1e-100, for example. The result is 1e100.
    /// This is because we can't fit 200 OOMs of precision into the result.
    /// However, we can easily fit ~26-33 decimals of precision into values,
    /// which covers most or all token supplies and amounts we care about in
    /// practice. This means that addition is typically lossless for all values
    /// we will receive onchain. However, precision loss is still to be expected
    /// when combined with other operations such as division that can result in
    /// infinite recursion such a 1/3.
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

        // Maximizing A and B gives us similar coefficients, which simplifies
        // detecting when their exponents are too far apart to add without
        // simply ignoring one of them.
        (signedCoefficientA, exponentA) = maximize(signedCoefficientA, exponentA);
        (signedCoefficientB, exponentB) = maximize(signedCoefficientB, exponentB);

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

        // After maximization the signed coefficients are the same OOM in
        // magnitude. However, what we need is for the exponents to be the same.
        // If the exponents are close enough we can divide coefficient B by
        // some power of 10 to align their exponents without precision loss.
        // If the exponents are too far apart, then all the information in B
        // would be lost, so we can just ignore B and return A.
        unchecked {
            uint256 alignmentExponentDiff = uint256(exponentA - exponentB);
            // The early return here allows us to do unchecked pow on the
            // scaler and means we never revert due to overflow here.
            if (alignmentExponentDiff > ADD_MAX_EXPONENT_DIFF) {
                return (signedCoefficientA, exponentA);
            }
            signedCoefficientB /= int256(10 ** alignmentExponentDiff);
        }

        // The actual addition step.
        unchecked {
            int256 c = signedCoefficientA + signedCoefficientB;
            bool didOverflow;
            assembly ("memory-safe") {
                let sameSignAB := iszero(shr(0xff, xor(signedCoefficientA, signedCoefficientB)))
                let sameSignAC := iszero(shr(0xff, xor(signedCoefficientA, c)))
                didOverflow := and(sameSignAB, iszero(sameSignAC))
            }
            // Be careful to handle overflow.
            if (didOverflow) {
                signedCoefficientA /= 10;
                signedCoefficientB /= 10;
                exponentA += 1;
                signedCoefficientA += signedCoefficientB;
            } else {
                signedCoefficientA = c;
            }
        }
        return (signedCoefficientA, exponentA);
    }

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
            compareRescale(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        return signedCoefficientA == signedCoefficientB;
    }

    /// Inverts a float. Equivalent to `1 / x`.
    function inv(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        return div(1e76, -76, signedCoefficient, exponent);
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
                if (signedCoefficient <= 0) {
                    if (signedCoefficient == 0) {
                        revert Log10Zero();
                    } else {
                        revert Log10Negative(signedCoefficient, exponent);
                    }
                }
                (signedCoefficient, exponent) = maximize(signedCoefficient, exponent);
            }

            // all powers of 10 look like 1 with a different exponent
            if (signedCoefficient == 1e76) {
                return (exponent + 76, 0);
            }
            bool isAtLeastE76 = signedCoefficient >= 1e76;

            // This is a positive log. i.e. log(x) where x >= 1.
            if (exponent > (isAtLeastE76 ? -77 : -76)) {
                int256 y1Coefficient;
                int256 y2Coefficient;
                int256 x1Coefficient;
                int256 x2Coefficient;
                int256 x1Exponent = exponent;
                bool interpolate;

                // Table lookup.
                {
                    assembly ("memory-safe") {
                        //slither-disable-next-line divide-before-multiply
                        function lookupTableVal(tables, index) -> result {
                            // First byte of the data contract must be skipped.
                            let mainOffset := add(1, mul(div(index, 10), 2))
                            mstore(0, 0)
                            extcodecopy(tables, 30, mainOffset, 2)
                            let mainTableVal := mload(0)

                            result := and(mainTableVal, 0x7FFF)
                            // Skip first byte of data contract then 1820 bytes
                            // of the log tables.
                            let smallTableOffset := 1821
                            if iszero(iszero(and(mainTableVal, 0x8000))) {
                                // Small table is half the size of the main
                                // table.
                                smallTableOffset := add(smallTableOffset, 910)
                            }

                            mstore(0, 0)
                            extcodecopy(
                                tables, 31, add(smallTableOffset, add(mul(div(index, 100), 10), mod(index, 10))), 1
                            )
                            result := add(result, mload(0))
                        }

                        // let scale := 1e72;
                        let scale := 1000000000000000000000000000000000000000000000000000000000000000000000000
                        if isAtLeastE76 { scale := mul(scale, 10) }

                        // Truncate the signed coefficient to what we can look
                        // up in the table.
                        // Slither false positive because the truncation is
                        // deliberate here.
                        //slither-disable-next-line divide-before-multiply
                        x1Coefficient := div(signedCoefficient, scale)
                        let idx := sub(x1Coefficient, 1000)
                        x1Coefficient := mul(x1Coefficient, scale)
                        x2Coefficient := add(x1Coefficient, scale)

                        if isAtLeastE76 { scale := div(scale, 10) }

                        y1Coefficient := mul(scale, lookupTableVal(tablesDataContract, idx))

                        interpolate := iszero(eq(x1Coefficient, signedCoefficient))

                        if interpolate { y2Coefficient := mul(scale, lookupTableVal(tablesDataContract, add(idx, 1))) }
                    }
                }

                if (interpolate) {
                    (signedCoefficient, exponent) = unitLinearInterpolation(
                        x1Coefficient, signedCoefficient, x2Coefficient, exponent, y1Coefficient, y2Coefficient, -76
                    );
                } else {
                    signedCoefficient = y1Coefficient;
                    exponent = -76;
                }
                return add(signedCoefficient, exponent, x1Exponent + (isAtLeastE76 ? int256(76) : int256(75)), 0);
            }
            // This is a negative log. i.e. log(x) where 0 < x < 1.
            // log(x) = -log(1/x)
            else {
                (signedCoefficient, exponent) = inv(signedCoefficient, exponent);
                (signedCoefficient, exponent) = log10(tablesDataContract, signedCoefficient, exponent);
                return minus(signedCoefficient, exponent);
            }
        }
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
    function pow10(address tablesDataContract, int256 signedCoefficient, int256 exponent)
        internal
        view
        returns (int256, int256)
    {
        unchecked {
            if (signedCoefficient < 0) {
                (signedCoefficient, exponent) = minus(signedCoefficient, exponent);
                (signedCoefficient, exponent) = pow10(tablesDataContract, signedCoefficient, exponent);
                return inv(signedCoefficient, exponent);
            }

            // Table lookup.
            (int256 characteristicCoefficient, int256 mantissaCoefficient) =
                characteristicMantissa(signedCoefficient, exponent);
            int256 characteristicExponent = exponent;
            {
                (int256 idx, bool interpolate, int256 scale) = mantissa4(mantissaCoefficient, exponent);
                (int256 y1Coefficient, int256 y2Coefficient) =
                    lookupAntilogTableY1Y2(tablesDataContract, uint256(idx), interpolate);
                if (interpolate) {
                    (signedCoefficient, exponent) = unitLinearInterpolation(
                        idx * scale, mantissaCoefficient, (idx + 1) * scale, exponent, y1Coefficient, y2Coefficient, -4
                    );
                } else {
                    signedCoefficient = y1Coefficient;
                    exponent = -4;
                }
            }

            return (
                signedCoefficient,
                1 + exponent + withTargetExponent(characteristicCoefficient, characteristicExponent, 0)
            );
        }
    }

    function maximize(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        unchecked {
            if (signedCoefficient == 0) {
                return (MAXIMIZED_ZERO_SIGNED_COEFFICIENT, MAXIMIZED_ZERO_EXPONENT);
            }
            int256 initialExponent = exponent;

            // Check if already maximized before dropping into a block full of
            // jumps.
            if (signedCoefficient / 1e75 == 0) {
                if (signedCoefficient / 1e38 == 0) {
                    signedCoefficient *= 1e38;
                    exponent -= 38;
                }

                if (signedCoefficient / 1e57 == 0) {
                    signedCoefficient *= 1e19;
                    exponent -= 19;
                }

                if (signedCoefficient / 1e66 == 0) {
                    signedCoefficient *= 1e10;
                    exponent -= 10;
                }

                while (signedCoefficient / 1e74 == 0) {
                    signedCoefficient *= 1e2;
                    exponent -= 2;
                }

                if (signedCoefficient / 1e75 == 0) {
                    signedCoefficient *= 10;
                    exponent -= 1;
                }
            }

            // Maybe we can fit in one more OOM without overflow, but we won't
            // know until we try. This pushes us into [1e76,type(int256).max] and
            // [-type(int256).max,-1e76] ranges, if that's possible.
            int256 trySignedCoefficient = signedCoefficient * 10;
            if (signedCoefficient == trySignedCoefficient / 10) {
                signedCoefficient = trySignedCoefficient;
                exponent -= 1;
            }

            if (initialExponent < exponent) {
                revert ExponentOverflow(signedCoefficient, initialExponent);
            }

            return (signedCoefficient, exponent);
        }
    }

    function isNormalized(int256 signedCoefficient, int256 exponent) internal pure returns (bool) {
        bool result;
        uint256 normalizedMaxPlusOne = NORMALIZED_MAX_PLUS_ONE;
        uint256 normalizedMin = NORMALIZED_MIN;
        assembly {
            result :=
                or(
                    and(
                        iszero(sdiv(signedCoefficient, normalizedMaxPlusOne)),
                        iszero(iszero(sdiv(signedCoefficient, normalizedMin)))
                    ),
                    and(iszero(signedCoefficient), iszero(exponent))
                )
        }
        return result;
    }

    /// Rescale two floats so that they are possible to directly compare using
    /// standard operators on the signed coefficient.
    ///
    /// There is no guarantee that the returned values somehow represent the
    /// input values. The only guarantee is that comparing them directly will
    /// give the same result as comparing the inputs as floats.
    ///
    /// https://speleotrove.com/decimal/daops.html#refnumco
    /// > compare takes two operands and compares their values numerically. If
    /// > either operand is a special value then the general rules apply. No
    /// > flags are set unless an operand is a signaling NaN.
    /// >
    /// > Otherwise, the operands are compared as follows.
    /// >
    /// > If the signs of the operands differ, a value representing each operand
    /// > (’-1’ if the operand is less than zero, ’0’ if the operand is zero or
    /// > negative zero, or ’1’ if the operand is greater than zero) is used in
    /// > place of that operand for the comparison instead of the actual operand.
    /// >
    /// > The comparison is then effected by subtracting the second operand from
    /// > the first and then returning a value according to the result of the
    /// > subtraction: ’-1’ if the result is less than zero, ’0’ if the result is
    /// > zero or negative zero, or ’1’ if the result is greater than zero.
    /// >
    /// > An implementation may use this operation ‘under the covers’ to
    /// > implement a closed set of comparison operations
    /// > (greater than, equal,etc.) if desired. It need not, in this case,
    /// > expose the compare operation itself.
    function compareRescale(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
        unchecked {
            // There are special cases where the signed coefficients can be
            // compared directly, ignoring their exponents, without rescaling:
            // - Either is zero
            // - They have different signs
            // - Their exponents are equal
            {
                bool noopRescale;
                assembly ("memory-safe") {
                    noopRescale :=
                        or(
                            or(
                                // Either is zero
                                or(iszero(signedCoefficientA), iszero(signedCoefficientB)),
                                // They have different signs
                                xor(slt(signedCoefficientA, 0), slt(signedCoefficientB, 0))
                            ),
                            // Their exponents are equal
                            eq(exponentA, exponentB)
                        )
                }
                if (noopRescale) {
                    return (signedCoefficientA, signedCoefficientB);
                }
            }

            bool didSwap = false;
            if (exponentB > exponentA) {
                int256 tmp = signedCoefficientA;
                signedCoefficientA = signedCoefficientB;
                signedCoefficientB = tmp;

                tmp = exponentA;
                exponentA = exponentB;
                exponentB = tmp;

                didSwap = true;
            }

            int256 exponentDiff = exponentA - exponentB;
            bool didOverflow;
            assembly ("memory-safe") {
                didOverflow := or(slt(exponentDiff, 0), sgt(exponentDiff, 76))
            }
            if (didOverflow) {
                if (didSwap) {
                    return (0, signedCoefficientA);
                } else {
                    return (signedCoefficientA, 0);
                }
            }
            int256 scale = int256(10 ** uint256(exponentDiff));
            int256 rescaled = signedCoefficientA * scale;

            if (rescaled / scale != signedCoefficientA) {
                if (didSwap) {
                    return (0, signedCoefficientA);
                } else {
                    return (signedCoefficientA, 0);
                }
            } else if (didSwap) {
                return (signedCoefficientB, rescaled);
            } else {
                return (rescaled, signedCoefficientB);
            }
        }
    }

    /// Sets the coefficient so that exponent is the target exponent. Truncates
    /// the coefficient if shrinking, will error on overflow when growing.
    /// @param signedCoefficient The signed coefficient.
    /// @param exponent The exponent.
    /// @param targetExponent The target exponent.
    /// @return The new signed coefficient.
    function withTargetExponent(int256 signedCoefficient, int256 exponent, int256 targetExponent)
        internal
        pure
        returns (int256)
    {
        unchecked {
            if (exponent == targetExponent) {
                return signedCoefficient;
            } else if (targetExponent > exponent) {
                int256 exponentDiff = targetExponent - exponent;
                if (exponentDiff > 76 || exponentDiff < 0) {
                    return (MAXIMIZED_ZERO_SIGNED_COEFFICIENT);
                }

                return signedCoefficient / int256(10 ** uint256(exponentDiff));
            } else {
                int256 exponentDiff = exponent - targetExponent;
                if (exponentDiff > 76 || exponentDiff < 0) {
                    revert WithTargetExponentOverflow(signedCoefficient, exponent, targetExponent);
                }
                int256 scale = int256(10 ** uint256(exponentDiff));
                int256 rescaled = signedCoefficient * scale;
                if (rescaled / scale != signedCoefficient) {
                    revert WithTargetExponentOverflow(signedCoefficient, exponent, targetExponent);
                }
                return rescaled;
            }
        }
    }

    function characteristicMantissa(int256 signedCoefficient, int256 exponent)
        internal
        pure
        returns (int256 characteristic, int256 mantissa)
    {
        unchecked {
            // if exponent is not negative the characteristic is the number
            // itself and the mantissa is 0.
            if (exponent >= 0) {
                return (signedCoefficient, 0);
            }

            // If the exponent is less than -76, the characteristic is 0.
            // and the mantissa is the whole coefficient.
            if (exponent < -76) {
                return (0, signedCoefficient);
            }

            int256 unit = int256(10 ** uint256(-exponent));
            mantissa = signedCoefficient % unit;
            characteristic = signedCoefficient - mantissa;
        }
    }

    /// First 4 digits of the mantissa and whether we need to interpolate.
    function mantissa4(int256 signedCoefficient, int256 exponent) internal pure returns (int256, bool, int256) {
        unchecked {
            if (exponent == -4) {
                return (signedCoefficient, false, 1);
            } else if (exponent < -4) {
                if (exponent < -80) {
                    return (0, signedCoefficient != 0, 1);
                }
                int256 scale = int256(10 ** uint256(-(exponent + 4)));
                //slither-disable-next-line divide-before-multiply
                int256 rescaled = signedCoefficient / scale;
                return (rescaled, rescaled * scale != signedCoefficient, scale);
            } else if (exponent >= 0) {
                return (0, false, 1);
            } else {
                // exponent is [-3, -1]
                return (signedCoefficient * int256(10 ** uint256(4 + exponent)), false, 1);
            }
        }
    }

    function lookupAntilogTableY1Y2(address tablesDataContract, uint256 idx, bool lossyIdx)
        internal
        view
        returns (int256 y1Coefficient, int256 y2Coefficient)
    {
        assembly ("memory-safe") {
            //slither-disable-next-line divide-before-multiply
            function lookupTableVal(tables, index) -> result {
                // 1 byte for start of data contract
                // + 1820 for log tables
                // + 910 for small log tables
                // + 100 for alt small log tables
                let offset := 2831
                mstore(0, 0)
                extcodecopy(tables, 30, add(offset, mul(div(index, 10), 2)), 2)
                let mainTableVal := mload(0)

                offset := add(offset, 2020)
                mstore(0, 0)
                extcodecopy(tables, 31, add(offset, add(mul(div(index, 100), 10), mod(index, 10))), 1)
                result := add(mainTableVal, mload(0))
            }

            y1Coefficient := lookupTableVal(tablesDataContract, idx)
            if lossyIdx { y2Coefficient := lookupTableVal(tablesDataContract, add(idx, 1)) }
        }
    }

    // Linear interpolation.
    // y = y1 + ((x - x1) * (y2 - y1)) / (x2 - x1)
    function unitLinearInterpolation(
        int256 x1Coefficient,
        int256 xCoefficient,
        int256 x2Coefficient,
        int256 xExponent,
        int256 y1Coefficient,
        int256 y2Coefficient,
        int256 yExponent
    ) internal pure returns (int256, int256) {
        int256 numeratorSignedCoefficient;
        int256 numeratorExponent;

        {
            // x - x1
            (int256 xDiffCoefficient0, int256 xDiffExponent0) = sub(xCoefficient, xExponent, x1Coefficient, xExponent);

            // y2 - y1
            (int256 yDiffCoefficient, int256 yDiffExponent) = sub(y2Coefficient, yExponent, y1Coefficient, yExponent);

            // (x - x1) * (y2 - y1)
            (numeratorSignedCoefficient, numeratorExponent) =
                mul(xDiffCoefficient0, xDiffExponent0, yDiffCoefficient, yDiffExponent);
        }

        // x2 - x1
        (int256 xDiffCoefficient1, int256 xDiffExponent1) = sub(x2Coefficient, xExponent, x1Coefficient, xExponent);

        // ((x - x1) * (y2 - y1)) / (x2 - x1)
        (int256 yMarginalSignedCoefficient, int256 yMarginalExponent) =
            div(numeratorSignedCoefficient, numeratorExponent, xDiffCoefficient1, xDiffExponent1);

        // y1 + ((x - x1) * (y2 - y1)) / (x2 - x1)
        (int256 signedCoefficient, int256 exponent) =
            add(yMarginalSignedCoefficient, yMarginalExponent, y1Coefficient, yExponent);
        return (signedCoefficient, exponent);
    }
}
