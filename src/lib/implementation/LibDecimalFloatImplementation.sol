// SPDX-License-Identifier: CAL
pragma solidity ^0.8.25;

import {ExponentOverflow} from "../../error/ErrDecimalFloat.sol";

/// @dev The minimum exponent that can be normalized.
/// This is crazy small, so should never be a problem for any real use case.
/// We need it to guard against overflow when normalizing.
int256 constant EXPONENT_MIN = type(int128).min + 79;

/// @dev The maximum exponent that can be normalized.
/// This is crazy large, so should never be a problem for any real use case.
/// We need it to guard against overflow when normalizing.
int256 constant EXPONENT_MAX = type(int128).max - 78;
int256 constant EXPONENT_MAX_PLUS_ONE = EXPONENT_MAX + 1;

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

/// @dev The signed coefficient of zero when normalized.
int256 constant NORMALIZED_ZERO_SIGNED_COEFFICIENT = 0;
/// @dev The exponent of zero when normalized.
int256 constant NORMALIZED_ZERO_EXPONENT = 0;

library LibDecimalFloatImplementation {
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

    function normalize(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        unchecked {
            if (isNormalized(signedCoefficient, exponent)) {
                return (signedCoefficient, exponent);
            }

            if (signedCoefficient == 0) {
                return (NORMALIZED_ZERO_SIGNED_COEFFICIENT, NORMALIZED_ZERO_EXPONENT);
            }

            if (exponent / EXPONENT_MAX_PLUS_ONE != 0) {
                revert ExponentOverflow(signedCoefficient, exponent);
            }

            if (signedCoefficient / (SIGNED_NORMALIZED_MAX + 1) != 0) {
                while (signedCoefficient / NORMALIZED_JUMP_DOWN_THRESHOLD != 0) {
                    signedCoefficient /= PRECISION_JUMP_MULTIPLIER;
                    exponent += EXPONENT_JUMP_SIZE;
                }

                while (signedCoefficient / (SIGNED_NORMALIZED_MAX + 1) != 0) {
                    signedCoefficient /= EXPONENT_STEP_MULTIPLIER;
                    exponent += EXPONENT_STEP_SIZE;
                }
            } else {
                while (NORMALIZED_JUMP_UP_THRESHOLD / signedCoefficient != 0) {
                    signedCoefficient *= PRECISION_JUMP_MULTIPLIER;
                    exponent -= EXPONENT_JUMP_SIZE;
                }

                while ((SIGNED_NORMALIZED_MIN - 1) / signedCoefficient != 0) {
                    signedCoefficient *= EXPONENT_STEP_MULTIPLIER;
                    exponent -= EXPONENT_STEP_SIZE;
                }
            }

            return (signedCoefficient, exponent);
        }
    }

    /// Rescale two floats so that they are possible to directly compare using
    /// standard operators on the signed coefficient.
    ///
    /// This works by taking the number with the larger exponent and raising it
    /// to the power of 10^(largerExponent - smallerExponent), then reducing its
    /// float exponent by the diff. This gives both floats the same exponent,
    /// which makes their signed coefficients directly comparable.
    ///
    /// In the case that rescaling causes an overflow, this means that the
    /// rescaled number is larger than the unscaled number. We cannot directly
    /// return the rescaled number, so instead we return 1, 0 for the larger and
    /// 0, 0 for the smaller. This way, comparisons can still be done at all
    /// scales.
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
                    return (0, 1);
                } else {
                    return (1, 0);
                }
            }
            int256 scale = int256(10 ** uint256(exponentDiff));
            int256 rescaled = signedCoefficientA * scale;

            if (rescaled / scale != signedCoefficientA) {
                if (didSwap) {
                    return (0, 1);
                } else {
                    return (1, 0);
                }
            } else if (didSwap) {
                return (signedCoefficientB, rescaled);
            } else {
                return (rescaled, signedCoefficientB);
            }
        }
    }
}
