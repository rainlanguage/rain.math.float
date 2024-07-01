// SPDX-License-Identifier: CAL
pragma solidity ^0.8.25;

import {
    LOG_TABLES,
    LOG_TABLES_SMALL,
    LOG_TABLES_SMALL_ALT,
    ANTI_LOG_TABLES,
    ANTI_LOG_TABLES_SMALL
} from "./generated/LogTables.pointers.sol";

error ExponentOverflow();
error NegativeFixedDecimalConversion(int256 signedCoefficient, int256 exponent);
error DivisionByZero();
error Log10Zero();
error Log10Negative(int256 signedCoefficient, int256 exponent);

/// @dev Currently we limit the coefficient bits to 128 so that operations like
/// multiplication can be done with 256 bit integers and be guaranteed not to
/// overflow.
uint256 constant COEFFICIENT_BITS = 127;
uint256 constant COEFFICIENT_MASK = (1 << COEFFICIENT_BITS) - 1;

uint256 constant SIGNED_COEFFICIENT_BITS = 128;
uint256 constant SIGNED_COEFFICIENT_MASK = type(uint128).max;

uint256 constant EXPONENT_BITS = 16;
uint256 constant EXPONENT_MASK = type(uint16).max;

uint128 constant SIGN_MASK = 1 << 0x7F;

int256 constant COMPARE_LESS_THAN = -1;
int256 constant COMPARE_EQUAL = 0;
int256 constant COMPARE_GREATER_THAN = 1;

int256 constant PRECISION_LEAP_SIZE = 24;
int256 constant PRECISION_LEAP_MULTIPLIER = int256(uint256(10 ** uint256(PRECISION_LEAP_SIZE)));

int256 constant PRECISION_JUMP_SIZE = 6;
int256 constant PRECISION_JUMP_MULTIPLIER = int256(uint256(10 ** uint256(PRECISION_JUMP_SIZE)));

int256 constant PRECISION_STEP_SIZE = 1;
int256 constant PRECISION_STEP_MULTIPLIER = int256(uint256(10 ** uint256(PRECISION_STEP_SIZE)));

int256 constant MINUS_MIN = (int256(type(int128).min) / -10) + 1;

uint256 constant NORMALIZED_MAX = 1e38 - 1;

int256 constant NORMALIZED_ZERO_SIGNED_COEFFICIENT = 0;
int256 constant NORMALIZED_ZERO_EXPONENT = -37;

library LibDecimalFloat {
    /// Convert a fixed point decimal value to a signed coefficient and exponent.
    /// The returned value will be normalized and the conversion is lossy if this
    /// results in a division that causes truncation. This can only happen if the
    /// value is greater than `NORMALIZED_MAX`, which is 10^38 - 1. For most use
    /// cases, this is not a concern and the conversion will always be lossless.
    /// @param value The fixed point decimal value to convert.
    /// @param decimals The number of decimals in the fixed point representation.
    /// e.g. If 1e18 represents 1 this would be 18 decimals.
    /// @return signedCoefficient The signed coefficient of the floating point
    /// representation.
    /// @return exponent The exponent of the floating point representation.
    /// @return lossless `true` if the conversion is lossless.
    function fromFixedDecimalLossy(uint256 value, uint8 decimals) internal pure returns (int256, int256, bool) {
        unchecked {
            uint256 unsignedCoefficient = value;
            int256 exponent = 0;
            while (unsignedCoefficient > NORMALIZED_MAX) {
                unsignedCoefficient /= 10;
                exponent += 1;
            }

            (int256 signedCoefficient, int256 finalExponent) =
                normalize(int256(unsignedCoefficient), exponent - int256(uint256(decimals)));
            return (
                signedCoefficient,
                finalExponent,
                unsignedCoefficient <= NORMALIZED_MAX || unsignedCoefficient * (10 ** uint256(exponent)) == value
            );
        }
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
        if (signedCoefficient < 0) {
            revert NegativeFixedDecimalConversion(signedCoefficient, exponent);
        } else if (signedCoefficient == 0) {
            return (0, true);
        } else {
            uint256 unsignedCoefficient = uint256(signedCoefficient);
            int256 finalExponent = exponent + int256(uint256(decimals));
            uint256 scale;
            uint256 fixedDecimal;
            if (finalExponent < 0) {
                scale = 10 ** uint256(-finalExponent);
                unchecked {
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
                    return (fixedDecimal, fixedDecimal / scale == unsignedCoefficient);
                }
            } else {
                return (unsignedCoefficient, true);
            }
        }
    }

    function pack(int256 signedCoefficient, int256 exponent) internal pure returns (uint256) {
        return uint256(uint128(int128(signedCoefficient))) | (uint256(uint128(int128(exponent))) << 0x80);
    }

    function unpack(uint256 packed) internal pure returns (int256, int256) {
        return (int128(uint128(packed)), int128(uint128(packed >> 0x80)));
    }

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
    function add(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
        (int256 signedCoefficientC, int256 exponentC) =
            addRaw(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        return normalize(signedCoefficientC, exponentC);
    }

    function addRaw(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
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
                unchecked {
                    alignmentExponentDiff = uint256(largerExponent - smallerExponent);
                }
                uint256 multiplier = 10 ** alignmentExponentDiff;
                if (multiplier > uint256(type(int256).max)) {
                    revert ExponentOverflow();
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

        return (adjustedCoefficient, smallerExponent);
    }

    function sub(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
        (signedCoefficientB, exponentB) = minus(signedCoefficientB, exponentB);
        return add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// https://speleotrove.com/decimal/daops.html#refplusmin
    /// > minus and plus both take one operand, and correspond to the prefix
    /// > minus and plus operators in programming languages.
    /// >
    /// > The operations are evaluated using the same rules as add and subtract;
    /// > the operations plus(a) and minus(a)
    /// > (where a and b refer to any numbers) are calculated as the operations
    /// > add(’0’, a) and subtract(’0’, b) respectively, where the ’0’ has the
    /// > same exponent as the operand.
    function minus(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        unchecked {
            if (signedCoefficient == int256(type(int128).max)) {
                return (MINUS_MIN, exponent + 1);
            } else {
                return (-signedCoefficient, exponent);
            }
        }
    }

    /// https://speleotrove.com/decimal/daops.html#refabs
    /// > abs takes one operand. If the operand is negative, the result is the
    /// > same as using the minus operation on the operand. Otherwise, the result
    /// > is the same as using the plus operation on the operand.
    function abs(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        unchecked {
            if (signedCoefficient >= 0) {
                return (signedCoefficient, exponent);
            } else {
                return minus(signedCoefficient, exponent);
            }
        }
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
        if (signedCoefficientA == 0 || signedCoefficientB == 0) {
            return (NORMALIZED_ZERO_SIGNED_COEFFICIENT, NORMALIZED_ZERO_EXPONENT);
        }

        int256 signedCoefficient;
        // This can't overflow because we're multiplying 128 bit numbers in 256
        // bit space.
        unchecked {
            signedCoefficient = signedCoefficientA * signedCoefficientB;
        }
        int256 exponent = exponentA + exponentB;
        return normalize(signedCoefficient, exponent);
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
        returns (int256 signedCoefficient, int256 exponent)
    {
        (signedCoefficientA, exponentA) = normalize(signedCoefficientA, exponentA);
        (signedCoefficientB, exponentB) = normalize(signedCoefficientB, exponentB);

        unchecked {
            signedCoefficient = (signedCoefficientA * 1e38) / signedCoefficientB;
            exponent = exponentA - exponentB - 38;
        }

        (signedCoefficient, exponent) = normalize(signedCoefficient, exponent);
    }

    function inv(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        return divide(1e37, -37, signedCoefficient, exponent);
    }

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
    function compare(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256)
    {
        // We don't support negative zero.
        (signedCoefficientB, exponentB) = minus(signedCoefficientB, exponentB);
        // We want the un-normalized result so that rounding doesn't affect the
        // comparison.
        (int256 signedCoefficient,) = addRaw(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        if (signedCoefficient == 0) {
            return COMPARE_EQUAL;
        } else if (signedCoefficient < 0) {
            return COMPARE_LESS_THAN;
        } else {
            return COMPARE_GREATER_THAN;
        }
    }

    function normalize(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        unchecked {
            (signedCoefficient, exponent) = maximize(signedCoefficient, exponent);
            while (signedCoefficient >= 1e38 || signedCoefficient <= -1e38) {
                signedCoefficient /= 10;
                exponent += 1;
            }
            return (signedCoefficient, exponent);
        }
    }

    function maximize(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        unchecked {
            // already maximized.
            // very common when chaining operations.
            if (signedCoefficient >= 1e37) {
                return (signedCoefficient, exponent);
            }
            // 0 can't maximise as 0 * x = 0.
            if (signedCoefficient == 0) {
                return (0, 0);
            }

            int256 signedCoefficientMaximized = signedCoefficient * PRECISION_LEAP_MULTIPLIER;
            int256 exponentMaximized = exponent - PRECISION_LEAP_SIZE;

            while (int128(signedCoefficientMaximized) == int256(signedCoefficientMaximized)) {
                signedCoefficient = int128(signedCoefficientMaximized);
                exponent = exponentMaximized;

                signedCoefficientMaximized *= PRECISION_LEAP_MULTIPLIER;
                exponentMaximized -= PRECISION_LEAP_SIZE;
            }

            signedCoefficientMaximized = int256(signedCoefficient) * PRECISION_JUMP_MULTIPLIER;
            exponentMaximized = exponent - PRECISION_JUMP_SIZE;

            while (int128(signedCoefficientMaximized) == int256(signedCoefficientMaximized)) {
                signedCoefficient = int128(signedCoefficientMaximized);
                exponent = exponentMaximized;

                signedCoefficientMaximized *= PRECISION_JUMP_MULTIPLIER;
                exponentMaximized -= PRECISION_JUMP_SIZE;
            }

            signedCoefficientMaximized = int256(signedCoefficient) * PRECISION_STEP_MULTIPLIER;
            exponentMaximized = exponent - PRECISION_STEP_SIZE;

            while (int128(signedCoefficientMaximized) == int256(signedCoefficientMaximized)) {
                signedCoefficient = int128(signedCoefficientMaximized);
                exponent = exponentMaximized;

                signedCoefficientMaximized *= PRECISION_STEP_MULTIPLIER;
                exponentMaximized -= PRECISION_STEP_SIZE;
            }

            return (signedCoefficient, exponent);
        }
    }

    /// a^b = 10^(b * log10(a))
    function power(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        view
        returns (int256, int256)
    {
        (int256 signedCoefficient, int256 exponent) = log10(signedCoefficientA, exponentA);
        (signedCoefficient, exponent) = multiply(signedCoefficient, exponent, signedCoefficientB, exponentB);
        return power10(signedCoefficient, exponent);
    }

    function frac(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        (signedCoefficient, exponent) = normalize(signedCoefficient, exponent);

        // This is already a fraction.
        if (signedCoefficient == 0 || exponent < -37) {
            return (signedCoefficient, exponent);
        }

        int256 unitCoefficient = int256(1e37 / (10 ** uint256(exponent + 37)));

        return normalize(signedCoefficient % unitCoefficient, exponent);
    }

    /// Sets the coefficient so that exponent is -37. Truncates the coefficient
    /// if shrinking, will error on overflow.
    /// MAY produce UNNORMALIZED output.
    function withTargetExponent(int256 signedCoefficient, int256 exponent, int256 targetExponent)
        internal
        pure
        returns (int256)
    {
        if (exponent == targetExponent) {
            return signedCoefficient;
        } else if (exponent < targetExponent) {
            return signedCoefficient / int256(10 ** uint256(targetExponent - exponent));
        } else {
            return signedCoefficient * int256(10 ** uint256(exponent - targetExponent));
        }
    }

    function lookupAntilogTableY1Y2(uint256 idx) internal pure returns (int256 y1Coefficient, int256 y2Coefficient) {
        bytes memory table = ANTI_LOG_TABLES;
        bytes memory tableSmall = ANTI_LOG_TABLES_SMALL;
        assembly ("memory-safe") {
            function lookupTableVal(mainTable, smallTable, index) -> result {
                let mainIndex := div(index, 10)

                let mainTableVal := and(mload(add(mainTable, mul(2, add(mainIndex, 1)))), 0xFFFF)

                // Slither false positive because the truncation is deliberate
                // here.
                //slither-disable-next-line divide-before-multiply
                let smallTableOffset := add(1, mul(div(index, 100), 10))
                let smallTableVal := byte(31, mload(add(smallTable, add(mod(index, 10), smallTableOffset))))

                result := add(mainTableVal, smallTableVal)
            }

            y1Coefficient := lookupTableVal(table, tableSmall, idx)
            y2Coefficient := lookupTableVal(table, tableSmall, add(idx, 1))
        }
    }

    function power10(int256 signedCoefficient, int256 exponent) internal view returns (int256, int256) {
        unchecked {
            if (signedCoefficient < 0) {
                (signedCoefficient, exponent) = minus(signedCoefficient, exponent);
                (signedCoefficient, exponent) = power10(signedCoefficient, exponent);
                return inv(signedCoefficient, exponent);
            }

            // Table lookup.
            int256 mantissaCoefficient;
            int256 mantissaExponent;
            int256 characteristicSignedCoefficient;
            int256 characteristicExponent;
            {
                (mantissaCoefficient, mantissaExponent) = frac(signedCoefficient, exponent);
                (characteristicSignedCoefficient, characteristicExponent) =
                    sub(signedCoefficient, exponent, mantissaCoefficient, mantissaExponent);

                int256 xScale = 1e33;
                uint256 idx = uint256(withTargetExponent(mantissaCoefficient, mantissaExponent, -37) / xScale);
                int256 x1Coefficient = withTargetExponent(int256(idx) * xScale, -37, mantissaExponent);

                (int256 y1Coefficient, int256 y2Coefficient) = lookupAntilogTableY1Y2(idx);

                (signedCoefficient, exponent) = unitLinearInterpolation(
                    mantissaCoefficient, x1Coefficient, mantissaExponent, -41, y1Coefficient, y2Coefficient, -4
                );
            }

            return (
                signedCoefficient,
                1 + exponent + withTargetExponent(characteristicSignedCoefficient, characteristicExponent, 0)
            );
        }
    }

    // Linear interpolation.
    // y = y1 + ((x - x1) * (y2 - y1)) / (x2 - x1)
    function unitLinearInterpolation(
        int256 xCoefficient,
        int256 x1Coefficient,
        int256 xExponent,
        int256 xUnitExponent,
        int256 y1Coefficient,
        int256 y2Coefficient,
        int256 yExponent
    ) internal pure returns (int256, int256) {
        int256 numeratorSignedCoefficient;
        int256 numeratorExponent;

        {
            // x - x1
            (int256 xDiffCoefficient, int256 xDiffExponent) = sub(xCoefficient, xExponent, x1Coefficient, xExponent);

            // y2 - y1
            (int256 yDiffCoefficient, int256 yDiffExponent) = sub(y2Coefficient, yExponent, y1Coefficient, yExponent);

            // (x - x1) * (y2 - y1)
            (numeratorSignedCoefficient, numeratorExponent) =
                multiply(xDiffCoefficient, xDiffExponent, yDiffCoefficient, yDiffExponent);
        }

        // Diff between x2 and x1 is always 1 unit.
        (int256 yMarginalSignedCoefficient, int256 yMarginalExponent) =
            divide(numeratorSignedCoefficient, numeratorExponent, 1e37, xUnitExponent);

        // y1 + ((x - x1) * (y2 - y1)) / (x2 - x1)
        (int256 signedCoefficient, int256 exponent) =
            add(yMarginalSignedCoefficient, yMarginalExponent, y1Coefficient, yExponent);
        return (signedCoefficient, exponent);
    }

    function log10(int256 signedCoefficient, int256 exponent) internal view returns (int256, int256) {
        unchecked {
            {
                (signedCoefficient, exponent) = normalize(signedCoefficient, exponent);

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

                // Table lookup.
                {
                    bytes memory table = LOG_TABLES;
                    bytes memory tableSmall = LOG_TABLES_SMALL;
                    bytes memory tableSmallAlt = LOG_TABLES_SMALL_ALT;
                    uint256 scale = 1e34;

                    assembly ("memory-safe") {
                        function lookupTableVal(mainTable, smallTableMain, smallTableAlt, index) -> result {
                            let mainIndex := div(index, 10)
                            let mainTableVal := mload(add(mainTable, mul(2, add(mainIndex, 1))))

                            result := and(mainTableVal, 0x7FFF)
                            let smallTable := smallTableAlt
                            if iszero(and(mainTableVal, 0x8000)) { smallTable := smallTableMain }

                            result := add(result, byte(31, mload(add(smallTable, add(mod(index, 10), 1)))))
                        }

                        // Truncate the signed coefficient to what we can look
                        // up in the table.
                        // Slither false positive because the truncation is
                        // deliberate here.
                        //slither-disable-next-line divide-before-multiply
                        x1Coefficient := div(signedCoefficient, scale)
                        let index := sub(x1Coefficient, 1000)
                        x1Coefficient := mul(x1Coefficient, scale)

                        y1Coefficient := mul(scale, lookupTableVal(table, tableSmall, tableSmallAlt, index))
                        y2Coefficient := mul(scale, lookupTableVal(table, tableSmall, tableSmallAlt, add(index, 1)))
                    }
                }

                (signedCoefficient, exponent) = unitLinearInterpolation(
                    signedCoefficient, x1Coefficient, exponent, -39, y1Coefficient, y2Coefficient, -38
                );

                return add(signedCoefficient, exponent, x1Exponent + 37, 0);
            }
            // This is a negative log. i.e. log(x) where 0 < x < 1.
            // log(x) = -log(1/x)
            else {
                (signedCoefficient, exponent) = divide(1e37, -37, signedCoefficient, exponent);
                (signedCoefficient, exponent) = log10(signedCoefficient, exponent);
                return minus(signedCoefficient, exponent);
            }
        }
    }
}
