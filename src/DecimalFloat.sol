// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

// error SignOverflow(uint256 badSign);
error ExponentOverflow();
// error CoefficientOverflow(uint256 badCoefficient);

error NegativeFixedDecimalConversion(DecimalFloat value);

error DivisionByZero();

type DecimalFloat is uint256;

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

int128 constant PRECISION_JUMP_SIZE = 6;
int128 constant PRECISION_JUMP_MULTIPLIER = int128(uint128(10 ** uint128(PRECISION_JUMP_SIZE)));

int128 constant PRECISION_STEP_SIZE = 1;
int128 constant PRECISION_STEP_MULTIPLIER = int128(uint128(10 ** uint128(PRECISION_STEP_SIZE)));

library LibDecimalFloat {
    // function fromFixedDecimal(uint256 value, uint8 decimals) internal pure returns (DecimalFloat) {
    //     unchecked {
    //         return fromParts(0, value, int256(uint256(decimals)) * -1);
    //     }
    // }

    // function toFixedDecimal(DecimalFloat value, uint8 decimals) internal pure returns (uint256) {
    //     unchecked {
    //         (uint256 sign, uint256 coefficient, int256 exponent) = toParts(value);
    //         if (sign == 1) {
    //             revert NegativeFixedDecimalConversion(value);
    //         }
    //         return coefficient / (10 ** uint256(int256(uint256(decimals)) + exponent));
    //     }
    // }

    function fromParts(int128 signedCoefficient, int128 exponent) internal pure returns (DecimalFloat) {
        return DecimalFloat.wrap(uint256(uint128(signedCoefficient)) | (uint256(uint128(exponent)) << 0x80));
    }

    function toParts(DecimalFloat value) internal pure returns (int128 signedCoefficient, int128 exponent) {
        signedCoefficient = int128(uint128(DecimalFloat.unwrap(value)));
        exponent = int128(uint128(DecimalFloat.unwrap(value) >> 0x80));
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
    function add(DecimalFloat a, DecimalFloat b) internal pure returns (DecimalFloat) {
        (int128 signedCoefficientA, int128 exponentA) = toParts(a);
        (int128 signedCoefficientB, int128 exponentB) = toParts(b);

        int128 smallerExponent;
        int256 adjustedCoefficient;

        {
            int128 largerExponent;
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

            uint128 alignmentExponentDiff;
            unchecked {
                alignmentExponentDiff = uint128(largerExponent - smallerExponent);
            }
            uint256 multiplier = 10 ** alignmentExponentDiff;
            if (multiplier > uint256(type(int256).max)) {
                revert ExponentOverflow();
            }
            adjustedCoefficient *= int256(multiplier);

            // This can't overflow because the signed coefficient is 128 bits.
            // Worst case scenario is that one was aligned all the way to fill
            // the high 128 bits, which we add to the max low 128 bits, which
            // doesn't overflow.
            unchecked {
                adjustedCoefficient += staticCoefficient;
            }
        }

        (int128 signedCoefficient, int128 exponent) = normalize(adjustedCoefficient, smallerExponent);
        return fromParts(signedCoefficient, exponent);
    }

    function sub(DecimalFloat a, DecimalFloat b) internal pure returns (DecimalFloat) {
        return add(a, minus(b));
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
    function minus(DecimalFloat value) internal pure returns (DecimalFloat) {
        return DecimalFloat.wrap(DecimalFloat.unwrap(value) ^ SIGN_MASK);
    }

    /// https://speleotrove.com/decimal/daops.html#refabs
    /// > abs takes one operand. If the operand is negative, the result is the
    /// > same as using the minus operation on the operand. Otherwise, the result
    /// > is the same as using the plus operation on the operand.
    function abs(DecimalFloat value) internal pure returns (DecimalFloat) {
        return DecimalFloat.wrap(DecimalFloat.unwrap(value) & ~SIGN_MASK);
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
    function multiply(DecimalFloat a, DecimalFloat b) internal pure returns (DecimalFloat) {
        (int128 signedCoefficientA, int128 exponentA) = toParts(a);
        (int128 signedCoefficientB, int128 exponentB) = toParts(b);

        // This can't overflow because we're multiplying 128 bit numbers in 256
        // bit space.
        int256 signedCoefficient;
        unchecked {
            signedCoefficient = int256(signedCoefficientA) * int256(signedCoefficientB);
        }
        int128 exponent = exponentA + exponentB;

        (int128 normalizedCoefficient, int128 normalizedExponent) = normalize(signedCoefficient, exponent);
        return fromParts(normalizedCoefficient, normalizedExponent);
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
    function divide(DecimalFloat a, DecimalFloat b) internal pure returns (DecimalFloat) {
        (int128 signedCoefficientA, int128 exponentA) = toParts(a);
        if (signedCoefficientA == 0) {
            return DecimalFloat.wrap(0);
        }

        (int128 signedCoefficientB, int128 exponentB) = toParts(b);
        if (signedCoefficientB == 0) {
            revert DivisionByZero();
        }

        uint256 unsignedCoefficientA = uint256(uint128(signedCoefficientA) & ~SIGN_MASK);
        uint256 unsignedCoefficientB = uint256(uint128(signedCoefficientB) & ~SIGN_MASK);

        int128 adjust = 0;
        int256 resultCoefficient = 0;

        unchecked {
            while (unsignedCoefficientA < unsignedCoefficientB) {
                unsignedCoefficientA *= 10;
                adjust += 1;
            }

            uint256 tensB = unsignedCoefficientB * 10;
            while (unsignedCoefficientA >= tensB) {
                unsignedCoefficientB = tensB;
                tensB *= 10;
                adjust -= 1;
            }

            uint256 tmpCoefficientA = unsignedCoefficientA;

            while (true) {
                while (tmpCoefficientA >= unsignedCoefficientB) {
                    tmpCoefficientA -= unsignedCoefficientB;
                    resultCoefficient += 1;
                }

                // Discard this round as it caused precision loss in the result.
                if (int128(resultCoefficient) != int256(resultCoefficient)) {
                    break;
                }

                unsignedCoefficientA = tmpCoefficientA;

                if (tmpCoefficientA == 0 && adjust >= 0) {
                    break;
                }

                tmpCoefficientA *= 10;
                resultCoefficient *= 10;
                adjust += 1;
            }
        }

        int128 exponent = exponentA - exponentB - adjust;

        (int128 normalizedCoefficient, int128 normalizedExponent) = normalize(resultCoefficient, exponent);
        DecimalFloat value = fromParts(normalizedCoefficient, normalizedExponent);

        uint256 signBit = DecimalFloat.unwrap(a) & SIGN_MASK ^ DecimalFloat.unwrap(b) & SIGN_MASK;

        return DecimalFloat.wrap(DecimalFloat.unwrap(value) & ~SIGN_MASK | signBit);
    }

    function div2(DecimalFloat a, DecimalFloat b) internal pure returns (DecimalFloat) {
        (int128 signedCoefficientA, int128 exponentA) = toParts(a);
        if (signedCoefficientA == 0) {
            return DecimalFloat.wrap(0);
        }
        (signedCoefficientA, exponentA) = maximize(signedCoefficientA, exponentA);

        (int128 signedCoefficientB, int128 exponentB) = toParts(b);
        (signedCoefficientB, exponentB) = maximize(signedCoefficientB, exponentB);

        int256 signedCoefficient = int256(signedCoefficientA) / int256(signedCoefficientB);
        int128 exponent = exponentA - exponentB;

        (int128 normalizedCoefficient, int128 normalizedExponent) = normalize(signedCoefficient, exponent);
        (int128 minimizedCoefficient, int128 minimizedExponent) = minimize(normalizedCoefficient, normalizedExponent);
        return fromParts(minimizedCoefficient, minimizedExponent);
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
    function compare(DecimalFloat a, DecimalFloat b) internal pure returns (int256) {
        // We don't support negative zero.
        if (DecimalFloat.unwrap(a) & SIGN_MASK != DecimalFloat.unwrap(b) & SIGN_MASK) {
            return DecimalFloat.unwrap(a) & SIGN_MASK > 0 ? COMPARE_LESS_THAN : COMPARE_GREATER_THAN;
        }

        DecimalFloat result = sub(a, b);
        (int128 signedCoefficient,) = toParts(result);
        if (signedCoefficient == 0) {
            return COMPARE_EQUAL;
        }
        return signedCoefficient < 0 ? COMPARE_LESS_THAN : COMPARE_GREATER_THAN;
    }

    function normalize(int256 signedCoefficient, int128 exponent) internal pure returns (int128, int128) {
        unchecked {
            while (int128(signedCoefficient) != int256(signedCoefficient)) {
                signedCoefficient /= 10;
                exponent += 1;
            }
            return (int128(signedCoefficient), exponent);
        }
    }

    function maximize(int128 signedCoefficient, int128 exponent) internal pure returns (int128, int128) {
        unchecked {
            int256 signedCoefficientMaximized = int256(signedCoefficient) * PRECISION_JUMP_MULTIPLIER;
            int128 exponentMaximized = exponent - PRECISION_JUMP_SIZE;

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

    function minimize(int128 signedCoefficient, int128 exponent) internal pure returns (int128, int128) {
        unchecked {
            // Fast forward.
            while (signedCoefficient % PRECISION_JUMP_MULTIPLIER == 0) {
                signedCoefficient /= PRECISION_JUMP_MULTIPLIER;
                exponent += PRECISION_JUMP_SIZE;
            }
            // Finalize.
            while (signedCoefficient % PRECISION_STEP_MULTIPLIER == 0) {
                signedCoefficient /= PRECISION_STEP_MULTIPLIER;
                exponent += PRECISION_STEP_SIZE;
            }
            return (signedCoefficient, exponent);
        }
    }
}
