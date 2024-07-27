// SPDX-License-Identifier: CAL
pragma solidity ^0.8.25;

import {ExponentOverflow} from "../../error/ErrDecimalFloat.sol";
import {
    LOG_TABLES,
    LOG_TABLES_SMALL,
    LOG_TABLES_SMALL_ALT,
    ANTI_LOG_TABLES,
    ANTI_LOG_TABLES_SMALL
} from "../../generated/LogTables.pointers.sol";
import {LibDecimalFloat} from "../LibDecimalFloat.sol";

error WithTargetExponentOverflow(int256 signedCoefficient, int256 exponent, int256 targetExponent);

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

    /// Sets the coefficient so that exponent is -37. Truncates the coefficient
    /// if shrinking, will error on overflow when growing.
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
                    return (NORMALIZED_ZERO_SIGNED_COEFFICIENT);
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
            // and the mantissa is the number itself.
            if (exponent < -76) {
                return (0, signedCoefficient);
            }

            int256 unit = int256(10 ** uint256(-exponent));
            mantissa = signedCoefficient % unit;
            characteristic = signedCoefficient - mantissa;
        }
    }

    function mantissa4(int256 signedCoefficient, int256 exponent) internal pure returns (int256) {
        unchecked {
            if (exponent <= -4) {
                if (exponent < -80) {
                    return 0;
                }
                return signedCoefficient / int256(10 ** uint256(-(exponent + 4)));
            } else if (exponent >= 0) {
                return 0;
            } else {
                // exponent is [-3, -1]
                return signedCoefficient * int256(10 ** uint256(4 + exponent));
            }
        }
    }

    function lookupAntilogTableY1Y2(address tablesDataContract, uint256 idx)
        internal
        view
        returns (int256 y1Coefficient, int256 y2Coefficient)
    {
        assembly ("memory-safe") {
            function lookupTableVal(tables, index) -> result {
                // 1 byte for start of data contract
                // + 1800 for log tables
                // + 900 for small log tables
                // + 100 for alt small log tables
                let offset := 2801
                mstore(0, 0)
                extcodecopy(tables, 30, add(offset, mul(div(index, 10), 2)), 2)
                let mainTableVal := mload(0)

                offset := add(offset, 2000)
                mstore(0, 0)
                extcodecopy(tables, 31, add(offset, add(mul(div(index, 100), 10), mod(index, 10))), 1)
                result := add(mainTableVal, mload(0))
            }

            y1Coefficient := lookupTableVal(tablesDataContract, idx)
            y2Coefficient := lookupTableVal(tablesDataContract, add(idx, 1))
        }
    }

    // Linear interpolation.
    // y = y1 + ((x - x1) * (y2 - y1)) / (x2 - x1)
    function unitLinearInterpolation(
        int256 xCoefficient,
        int256 xExponent,
        int256 x1Coefficient,
        int256 x1Exponent,
        int256 xUnitExponent,
        int256 y1Coefficient,
        int256 y2Coefficient,
        int256 yExponent
    ) internal pure returns (int256, int256) {
        int256 numeratorSignedCoefficient;
        int256 numeratorExponent;

        {
            // x - x1
            (int256 xDiffCoefficient, int256 xDiffExponent) =
                LibDecimalFloat.sub(xCoefficient, xExponent, x1Coefficient, x1Exponent);

            // y2 - y1
            (int256 yDiffCoefficient, int256 yDiffExponent) =
                LibDecimalFloat.sub(y2Coefficient, yExponent, y1Coefficient, yExponent);

            // (x - x1) * (y2 - y1)
            (numeratorSignedCoefficient, numeratorExponent) =
                LibDecimalFloat.multiply(xDiffCoefficient, xDiffExponent, yDiffCoefficient, yDiffExponent);
        }

        // Diff between x2 and x1 is always 1 unit.
        (int256 yMarginalSignedCoefficient, int256 yMarginalExponent) =
            LibDecimalFloat.divide(numeratorSignedCoefficient, numeratorExponent, 1e37, xUnitExponent);

        // y1 + ((x - x1) * (y2 - y1)) / (x2 - x1)
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloat.add(yMarginalSignedCoefficient, yMarginalExponent, y1Coefficient, yExponent);
        return (signedCoefficient, exponent);
    }
}
