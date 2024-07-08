// SPDX-License-Identifier: CAL
pragma solidity ^0.8.25;

import {ExponentOverflow} from "../../error/ErrDecimalFloat.sol";

/// @dev The minimum exponent that can be normalized.
/// This is crazy small, so should never be a problem for any real use case.
/// We need it to guard against overflow when normalizing.
int256 constant EXPONENT_MIN = type(int128).min + 78;

/// @dev The maximum exponent that can be normalized.
/// This is crazy large, so should never be a problem for any real use case.
/// We need it to guard against overflow when normalizing.
int256 constant EXPONENT_MAX = type(int128).max - 78;

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
int256 constant NORMALIZED_JUMP_DOWN_THRESHOLD = NORMALIZED_MAX * PRECISION_JUMP_MULTIPLIER;
/// @dev Every value below this can jump up while normalizing without
/// overshooting the normalized range.
int256 constant NORMALIZED_JUMP_UP_THRESHOLD = NORMALIZED_MIN / PRECISION_JUMP_MULTIPLIER;

/// @dev The minimum absolute value of a normalized signed coefficient.
int256 constant NORMALIZED_MIN = 1e37;
/// @dev The maximum absolute value of a normalized signed coefficient.
int256 constant NORMALIZED_MAX = 1e38 - 1;

/// @dev The signed coefficient of zero when normalized.
int256 constant NORMALIZED_ZERO_SIGNED_COEFFICIENT = 0;
/// @dev The exponent of zero when normalized.
int256 constant NORMALIZED_ZERO_EXPONENT = -37;

library LibDecimalFloatImplementation {
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
    function addRaw(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
        (signedCoefficientA, exponentA) = normalize(signedCoefficientA, exponentA);
        (signedCoefficientB, exponentB) = normalize(signedCoefficientB, exponentB);

        int256 smallerExponent;
        int256 adjustedCoefficient;

        {
            int256 largerExponent;
            int256 staticCoefficient;
            if (exponentA > exponentB) {
                smallerExponent = exponentB;
                largerExponent = exponentA;
                adjustedCoefficient = signedCoefficientA;
                staticCoefficient = signedCoefficientB;
            } else {
                smallerExponent = exponentA;
                largerExponent = exponentB;
                adjustedCoefficient = signedCoefficientB;
                staticCoefficient = signedCoefficientA;
            }

            if (adjustedCoefficient > 0) {
                uint256 alignmentExponentDiff;
                uint256 multiplier;
                unchecked {
                    alignmentExponentDiff = uint256(largerExponent - smallerExponent);
                    if (alignmentExponentDiff > 76) {
                        revert ExponentOverflow();
                    }
                    multiplier = 10 ** alignmentExponentDiff;
                }

                adjustedCoefficient *= int256(multiplier);
            }

            // This can't overflow because the signed coefficient is 128 bits.
            // Worst case scenario is that one was aligned all the way to fill
            // the high 128 bits, which we add to the max low 128 bits, which
            // doesn't overflow.
            unchecked {
                adjustedCoefficient += staticCoefficient;
            }
        }

        return normalize(adjustedCoefficient, smallerExponent);
    }

    function isNormalized(int256 signedCoefficient, int256) internal pure returns (bool) {
        return signedCoefficient <= NORMALIZED_MAX && signedCoefficient >= NORMALIZED_MIN;
    }

    function normalize(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        unchecked {
            // Inlined version of `isNormalized` to avoid the function call
            // gas overhead. This is a very hot path.
            if (signedCoefficient <= NORMALIZED_MAX && signedCoefficient >= NORMALIZED_MIN) {
                return (signedCoefficient, exponent);
            }

            if (signedCoefficient == 0) {
                return (NORMALIZED_ZERO_SIGNED_COEFFICIENT, NORMALIZED_ZERO_EXPONENT);
            }

            // Need to do the exponent range check here before we attempt to
            // do unsigned math (potentially) in the negative coefficient case.
            // Need to do this after the normalization check to avoid adding
            // overhead to the hot path.
            if (exponent < EXPONENT_MIN || exponent > EXPONENT_MAX) {
                revert ExponentOverflow();
            }

            if (signedCoefficient < 0) {
                // This is a special case because we cannot negate the minimum
                // value of an int256 without overflow.
                // Note that if BOTH the coefficient is `type(int256).min` and
                // the exponent is `EXPONENT_MAX`, we will still overflow here.
                // This is due to the recursive nature of the normalization
                // for negative numbers, and the exponent increment here.
                if (signedCoefficient == type(int256).min) {
                    signedCoefficient /= 10;
                    exponent += 1;
                }
                (signedCoefficient, exponent) = normalize(-signedCoefficient, exponent);
                return (-signedCoefficient, exponent);
            }

            while (signedCoefficient >= NORMALIZED_JUMP_DOWN_THRESHOLD) {
                signedCoefficient /= PRECISION_JUMP_MULTIPLIER;
                exponent += EXPONENT_JUMP_SIZE;
            }

            while (signedCoefficient > NORMALIZED_MAX) {
                signedCoefficient /= EXPONENT_STEP_MULTIPLIER;
                exponent += EXPONENT_STEP_SIZE;
            }

            while (signedCoefficient < NORMALIZED_JUMP_UP_THRESHOLD) {
                signedCoefficient *= PRECISION_JUMP_MULTIPLIER;
                exponent -= EXPONENT_JUMP_SIZE;
            }

            while (signedCoefficient < NORMALIZED_MIN) {
                signedCoefficient *= EXPONENT_STEP_MULTIPLIER;
                exponent -= EXPONENT_STEP_SIZE;
            }

            return (signedCoefficient, exponent);
        }
    }
}
