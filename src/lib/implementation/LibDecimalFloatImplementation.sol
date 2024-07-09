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
int256 constant NORMALIZED_ZERO_EXPONENT = 0;

library LibDecimalFloatImplementation {
    function isNormalized(int256 signedCoefficient, int256 exponent) internal pure returns (bool) {
        unchecked {


        return (signedCoefficient / (NORMALIZED_MAX + 1) == 0 && signedCoefficient / NORMALIZED_MIN != 0)
            || (signedCoefficient == NORMALIZED_ZERO_SIGNED_COEFFICIENT && exponent == NORMALIZED_ZERO_EXPONENT);
        }
    }

    function normalize(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        unchecked {
            if (isNormalized(signedCoefficient, exponent)) {
                return (signedCoefficient, exponent);
            }

            if (signedCoefficient == 0) {
                return (NORMALIZED_ZERO_SIGNED_COEFFICIENT, NORMALIZED_ZERO_EXPONENT);
            }

            if (exponent < EXPONENT_MIN || exponent > EXPONENT_MAX) {
                revert ExponentOverflow(signedCoefficient, exponent);
            }

            while (signedCoefficient / NORMALIZED_JUMP_DOWN_THRESHOLD != 0) {
                signedCoefficient /= PRECISION_JUMP_MULTIPLIER;
                exponent += EXPONENT_JUMP_SIZE;
            }

            while (signedCoefficient / (NORMALIZED_MAX + 1) != 0) {
                signedCoefficient /= EXPONENT_STEP_MULTIPLIER;
                exponent += EXPONENT_STEP_SIZE;
            }

            while (NORMALIZED_JUMP_UP_THRESHOLD / signedCoefficient != 0) {
                signedCoefficient *= PRECISION_JUMP_MULTIPLIER;
                exponent -= EXPONENT_JUMP_SIZE;
            }

            while ((NORMALIZED_MIN - 1) / signedCoefficient != 0) {
                signedCoefficient *= EXPONENT_STEP_MULTIPLIER;
                exponent -= EXPONENT_STEP_SIZE;
            }

            return (signedCoefficient, exponent);
        }
    }
}
