// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

// import {console} from "forge-std/console.sol";

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

int256 constant PRECISION_LEAP_SIZE = 24;
int256 constant PRECISION_LEAP_MULTIPLIER = int256(uint256(10 ** uint256(PRECISION_LEAP_SIZE)));

int256 constant PRECISION_JUMP_SIZE = 6;
int256 constant PRECISION_JUMP_MULTIPLIER = int256(uint256(10 ** uint256(PRECISION_JUMP_SIZE)));

int256 constant PRECISION_STEP_SIZE = 1;
int256 constant PRECISION_STEP_MULTIPLIER = int256(uint256(10 ** uint256(PRECISION_STEP_SIZE)));

int256 constant MINUS_MIN = (int256(type(int128).min) / -10) + 1;

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

    function fromParts(int256 signedCoefficient, int256 exponent) internal pure returns (DecimalFloat) {
        return DecimalFloat.wrap(
            uint256(uint128(int128(signedCoefficient))) | (uint256(uint128(int128(exponent))) << 0x80)
        );
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
        // (int128 signedCoefficientA, int128 exponentA) = toParts(a);
        // (int128 signedCoefficientB, int128 exponentB) = toParts(b);

        // int128 smallerExponent;
        // int256 adjustedCoefficient;

        // {
        //     int128 largerExponent;
        //     int256 staticCoefficient;
        //     if (exponentA > exponentB) {
        //         smallerExponent = exponentB;
        //         largerExponent = exponentA;
        //         adjustedCoefficient = signedCoefficientA;
        //         staticCoefficient = signedCoefficientB;
        //     } else {
        //         smallerExponent = exponentA;
        //         largerExponent = exponentB;
        //         adjustedCoefficient = signedCoefficientB;
        //         staticCoefficient = signedCoefficientA;
        //     }

        //     if (adjustedCoefficient > 0) {
        //         uint128 alignmentExponentDiff;
        //         unchecked {
        //             alignmentExponentDiff = uint128(largerExponent - smallerExponent);
        //         }
        //         uint256 multiplier = 10 ** alignmentExponentDiff;
        //         if (multiplier > uint256(type(int256).max)) {
        //             revert ExponentOverflow();
        //         }
        //         adjustedCoefficient *= int256(multiplier);
        //     }

        //     // This can't overflow because the signed coefficient is 128 bits.
        //     // Worst case scenario is that one was aligned all the way to fill
        //     // the high 128 bits, which we add to the max low 128 bits, which
        //     // doesn't overflow.
        //     unchecked {
        //         adjustedCoefficient += staticCoefficient;
        //     }
        // }

        // (int128 signedCoefficient, int128 exponent) = normalize(adjustedCoefficient, smallerExponent);
        // return fromParts(signedCoefficient, exponent);
        (int256 signedCoefficientA, int256 exponentA) = toParts(a);
        (int256 signedCoefficientB, int256 exponentB) = toParts(b);
        (int256 signedCoefficient, int256 exponent) =
            addByParts(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        return fromParts(signedCoefficient, exponent);
    }

    function addByPartsRaw(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
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

    function addByParts(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
        (int256 signedCoefficient, int256 exponent) =
            addByPartsRaw(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        return normalize(signedCoefficient, exponent);
    }

    function subByParts(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
        (signedCoefficientB, exponentB) = minusByParts(signedCoefficientB, exponentB);
        return addByParts(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
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
    function minusByParts(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
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
    function absByParts(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        unchecked {
            if (signedCoefficient >= 0) {
                return (signedCoefficient, exponent);
            } else {
                return minusByParts(signedCoefficient, exponent);
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
    function multiply(DecimalFloat a, DecimalFloat b) internal pure returns (DecimalFloat) {
        (int256 signedCoefficientA, int256 exponentA) = toParts(a);
        (int256 signedCoefficientB, int256 exponentB) = toParts(b);

        // This can't overflow because we're multiplying 128 bit numbers in 256
        // bit space.
        int256 signedCoefficient;
        unchecked {
            signedCoefficient = int256(signedCoefficientA) * int256(signedCoefficientB);
        }
        int256 exponent = exponentA + exponentB;

        (int256 normalizedCoefficient, int256 normalizedExponent) = normalize(signedCoefficient, exponent);
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
    // function divide(DecimalFloat a, DecimalFloat b) internal pure returns (DecimalFloat) {
    //     (int128 signedCoefficientA, int128 exponentA) = toParts(a);
    //     if (signedCoefficientA == 0) {
    //         return DecimalFloat.wrap(0);
    //     }

    //     (int128 signedCoefficientB, int128 exponentB) = toParts(b);
    //     if (signedCoefficientB == 0) {
    //         revert DivisionByZero();
    //     }

    //     uint256 unsignedCoefficientA = uint256(uint128(signedCoefficientA) & ~SIGN_MASK);
    //     uint256 unsignedCoefficientB = uint256(uint128(signedCoefficientB) & ~SIGN_MASK);

    //     int128 adjust = 0;
    //     int256 resultCoefficient = 0;

    //     unchecked {
    //         while (unsignedCoefficientA < unsignedCoefficientB) {
    //             unsignedCoefficientA *= 10;
    //             adjust += 1;
    //         }

    //         uint256 tensB = unsignedCoefficientB * 10;
    //         while (unsignedCoefficientA >= tensB) {
    //             unsignedCoefficientB = tensB;
    //             tensB *= 10;
    //             adjust -= 1;
    //         }

    //         uint256 tmpCoefficientA = unsignedCoefficientA;

    //         while (true) {
    //             while (tmpCoefficientA >= unsignedCoefficientB) {
    //                 tmpCoefficientA -= unsignedCoefficientB;
    //                 resultCoefficient += 1;
    //             }

    //             // Discard this round as it caused precision loss in the result.
    //             if (int128(resultCoefficient) != int256(resultCoefficient)) {
    //                 break;
    //             }

    //             unsignedCoefficientA = tmpCoefficientA;

    //             if (tmpCoefficientA == 0 && adjust >= 0) {
    //                 break;
    //             }

    //             tmpCoefficientA *= 10;
    //             resultCoefficient *= 10;
    //             adjust += 1;
    //         }
    //     }

    //     int128 exponent = exponentA - exponentB - adjust;

    //     (int128 normalizedCoefficient, int128 normalizedExponent) = normalize(resultCoefficient, exponent);
    //     DecimalFloat value = fromParts(normalizedCoefficient, normalizedExponent);

    //     uint256 signBit = DecimalFloat.unwrap(a) & SIGN_MASK ^ DecimalFloat.unwrap(b) & SIGN_MASK;

    //     return DecimalFloat.wrap(DecimalFloat.unwrap(value) & ~SIGN_MASK | signBit);
    // }

    function divide2(DecimalFloat a, DecimalFloat b) internal pure returns (DecimalFloat) {
        // (int128 signedCoefficientA, int128 exponentA) = toParts(a);
        // if (signedCoefficientA == 0) {
        //     return DecimalFloat.wrap(0);
        // }
        // (signedCoefficientA, exponentA) = maximize(signedCoefficientA, exponentA);

        // (int128 signedCoefficientB, int128 exponentB) = toParts(b);
        // (signedCoefficientB, exponentB) = minimize(signedCoefficientB, exponentB);

        // int256 signedCoefficient = int256(signedCoefficientA) / int256(signedCoefficientB);
        // int128 exponent = exponentA - exponentB;

        // (int128 normalizedCoefficient, int128 normalizedExponent) = normalize(signedCoefficient, exponent);
        // // (int128 minimizedCoefficient, int128 minimizedExponent) = minimize(normalizedCoefficient, normalizedExponent);
        // return fromParts(normalizedCoefficient, normalizedExponent);

        (int256 signedCoefficientA, int256 exponentA) = toParts(a);
        (int256 signedCoefficientB, int256 exponentB) = toParts(b);
        (int256 signedCoefficient, int256 exponent) =
            divideByParts(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        return fromParts(signedCoefficient, exponent);
    }

    function divideByParts(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256 signedCoefficient, int256 exponent)
    {
        (signedCoefficientA, exponentA) = maximize(signedCoefficientA, exponentA);
        (signedCoefficientB, exponentB) = minimize(signedCoefficientB, exponentB);

        unchecked {
            signedCoefficient = signedCoefficientA / signedCoefficientB;
            exponent = exponentA - exponentB;
        }

        (signedCoefficient, exponent) = normalize(signedCoefficient, exponent);
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
    function compareByParts(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256)
    {
        // We don't support negative zero.
        (signedCoefficientB, exponentB) = minusByParts(signedCoefficientB, exponentB);
        // We want the un-normalized result so that rounding doesn't affect the
        // comparison.
        (int256 signedCoefficient,) = addByPartsRaw(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        if (signedCoefficient == 0) {
            return COMPARE_EQUAL;
        } else if (signedCoefficient < 0) {
            return COMPARE_LESS_THAN;
        } else {
            return COMPARE_GREATER_THAN;
        }

        // // We don't support negative zero.
        // // Because subtraction involves rounding if the two numbers are very far
        // // apart, better to just compare the maximized versions directly
        // (signedCoefficientA, exponentA) = maximize(signedCoefficientA, exponentA);
        // (signedCoefficientB, exponentB) = maximize(signedCoefficientB, exponentB);

        // // The signs are different so just check which is smaller.
        // if (uint256(signedCoefficientA) >> 0xFF != uint256(signedCoefficientB) >> 0xFF) {
        //     return signedCoefficientA < signedCoefficientB ? COMPARE_LESS_THAN : COMPARE_GREATER_THAN;
        // }

        // // The signs are the same so check the exponents.
        // if (exponentA > exponentB) {
        //     return COMPARE_GREATER_THAN;
        // } else if (exponentA < exponentB) {
        //     return COMPARE_LESS_THAN;
        // }

        // // The exponents are the same so just check the coefficient.
        // if (signedCoefficientA == signedCoefficientB) {
        //     return COMPARE_EQUAL;
        // } else if (signedCoefficientA < signedCoefficientB) {
        //     return COMPARE_LESS_THAN;
        // } else {
        //     return COMPARE_GREATER_THAN;
        // }
    }

    function compare(DecimalFloat a, DecimalFloat b) internal pure returns (int256) {
        (int256 signedCoefficientA, int256 exponentA) = toParts(a);
        (int256 signedCoefficientB, int256 exponentB) = toParts(b);
        return compareByParts(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    function normalize(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        unchecked {
            while (int128(signedCoefficient) != int256(signedCoefficient)) {
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

    /// https://www.ams.org/journals/mcom/1954-08-046/S0025-5718-1954-0061464-9/S0025-5718-1954-0061464-9.pdf
    function log10ByParts(int256 signedCoefficientB, int256 exponentB, uint256 precision)
        internal
        pure
        returns (int256, int256)
    {
        unchecked {
            // Maximizing B can make some comparisons faster.
            (signedCoefficientB, exponentB) = maximize(signedCoefficientB, exponentB);

            // We start with a0 in A, ax in B, 1 in C and F, and 0 in D and E. The
            // latest approximation to log a0 a1 is always E/F.
            // Maximised form of 10 is 1e38e-37
            int256 signedCoefficientA = 1e38;
            int256 exponentA = -37;

            // C and E get swapped to merge them. C is high 128 bits, E is low.
            // C initial is 1
            // E initial is 0
            uint256 ce = 1 << 0x80;

            // D and F get swapped to merge them. D is high 128 bits, F is low.
            // D initial is 0
            // F initial is 1
            uint256 df = 1;

            uint256 i = 0;
            while (i < precision) {
                // Operation II (if A < B) :
                if (compareByParts(signedCoefficientA, exponentA, signedCoefficientB, exponentB) == COMPARE_LESS_THAN) {
                    // We interchange A and B, C and E, D and F.
                    int256 tmpDecimalPart = signedCoefficientB;
                    signedCoefficientB = signedCoefficientA;
                    signedCoefficientA = tmpDecimalPart;

                    tmpDecimalPart = exponentB;
                    exponentB = exponentA;
                    exponentA = tmpDecimalPart;

                    ce = ce << 0x80 | ce >> 0x80;
                    df = df << 0x80 | df >> 0x80;

                    i++;
                }
                // Operation I (if A >= B) :
                else {
                    // We put A/B in A, C + E in C, and D + F in D.
                    (signedCoefficientA, exponentA) =
                        divideByParts(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

                    {
                        uint256 c = ce >> 0x80;
                        uint256 e = ce & type(uint128).max;
                        ce = ((c + e) << 0x80) | e;
                    }

                    {
                        uint256 d = df >> 0x80;
                        uint256 f = df & type(uint128).max;
                        df = ((d + f) << 0x80) | f;
                    }
                }

                // If it happens that the logarithm is a rational number, for
                // instance log8 4 = 2/3, then at some point B becomes 1, the exact
                // log is obtained and no further changes in E or F occurs.
                // Comparing a probably maximized B to a maximized one should be
                // most efficient to compare.
                if (compareByParts(signedCoefficientB, exponentB, 1e38, -38) == COMPARE_EQUAL) {
                    break;
                }
            }

            uint256 e = ce & type(uint128).max;
            uint256 f = df & type(uint128).max;
            return divideByParts(int256(e), 0, int256(f), 0);
        }
    }

    function minimize(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        unchecked {
            // Most likely is already maximally minimized or maximized.
            // Already minimized:
            if (int256(signedCoefficient % 10) > 0) {
                return (signedCoefficient, exponent);
            }

            if (int256(signedCoefficient % 1e32) == 0) {
                if (int256(signedCoefficient % 1e40) == 0) {
                    return (0, 0);
                }

                if (int256(signedCoefficient % 1e36) == 0) {
                    if (int256(signedCoefficient % 1e38) == 0) {
                        return (int256(signedCoefficient / 1e38), exponent + 38);
                    }

                    if (int256(signedCoefficient % 1e37) == 0) {
                        return (signedCoefficient / 1e37, exponent + 37);
                    }

                    return (int256(signedCoefficient / 1e36), exponent + 36);
                }

                if (int256(signedCoefficient % 1e34) == 0) {
                    if (int256(signedCoefficient % 1e35) == 0) {
                        return (signedCoefficient / 1e35, exponent + 35);
                    }

                    return (signedCoefficient / 1e34, exponent + 34);
                }

                if (int256(signedCoefficient % 1e33) == 0) {
                    return (signedCoefficient / 1e33, exponent + 33);
                }

                return (signedCoefficient / 1e32, exponent + 32);
            }

            if (int256(signedCoefficient % 1e16) == 0) {
                if (int256(signedCoefficient % 1e24) == 0) {
                    if (int256(signedCoefficient % 1e28) == 0) {
                        if (int256(signedCoefficient % 1e30) == 0) {
                            if (int256(signedCoefficient % 1e31) == 0) {
                                return (signedCoefficient / 1e31, exponent + 31);
                            }
                            return (signedCoefficient / 1e30, exponent + 30);
                        }
                        if (int256(signedCoefficient % 1e29) == 0) {
                            return (signedCoefficient / 1e29, exponent + 29);
                        }
                        return (signedCoefficient / 1e28, exponent + 28);
                    }
                    if (int256(signedCoefficient % 1e26) == 0) {
                        if (int256(signedCoefficient % 1e27) == 0) {
                            return (signedCoefficient / 1e27, exponent + 27);
                        }
                        return (signedCoefficient / 1e26, exponent + 26);
                    }
                    if (int256(signedCoefficient % 1e25) == 0) {
                        return (signedCoefficient / 1e25, exponent + 25);
                    }
                    return (signedCoefficient / 1e24, exponent + 24);
                }
                if (int256(signedCoefficient % 1e20) == 0) {
                    if (int256(signedCoefficient % 1e22) == 0) {
                        if (int256(signedCoefficient % 1e23) == 0) {
                            return (signedCoefficient / 1e23, exponent + 23);
                        }
                        return (signedCoefficient / 1e22, exponent + 22);
                    }
                    if (int256(signedCoefficient % 1e21) == 0) {
                        return (signedCoefficient / 1e21, exponent + 21);
                    }
                    return (signedCoefficient / 1e20, exponent + 20);
                }
                if (int256(signedCoefficient % 1e18) == 0) {
                    if (signedCoefficient % 1e19 == 0) {
                        return (signedCoefficient / 1e19, exponent + 19);
                    }
                    return (signedCoefficient / 1e18, exponent + 18);
                }
                if (int256(signedCoefficient % 1e17) == 0) {
                    return (signedCoefficient / 1e17, exponent + 17);
                }
                return (signedCoefficient / 1e16, exponent + 16);
            }

            if (int256(signedCoefficient % 1e8) == 0) {
                if (int256(signedCoefficient % 1e12) == 0) {
                    if (int256(signedCoefficient % 1e14) == 0) {
                        if (int256(signedCoefficient % 1e15) == 0) {
                            return (signedCoefficient / 1e15, exponent + 15);
                        }
                        return (signedCoefficient / 1e14, exponent + 14);
                    }
                    if (int256(signedCoefficient % 1e13) == 0) {
                        return (signedCoefficient / 1e13, exponent + 13);
                    }
                    return (signedCoefficient / 1e12, exponent + 12);
                }
                if (int256(signedCoefficient % 1e10) == 0) {
                    if (int256(signedCoefficient % 1e11) == 0) {
                        return (signedCoefficient / 1e11, exponent + 11);
                    }
                    return (signedCoefficient / 1e10, exponent + 10);
                }
                if (int256(signedCoefficient % 1e9) == 0) {
                    return (signedCoefficient / 1e9, exponent + 9);
                }
                return (signedCoefficient / 1e8, exponent + 8);
            }

            if (int256(signedCoefficient % 1e4) == 0) {
                if (int256(signedCoefficient % 1e6) == 0) {
                    if (int256(signedCoefficient % 1e7) == 0) {
                        return (signedCoefficient / 1e7, exponent + 7);
                    }
                    return (signedCoefficient / 1e6, exponent + 6);
                }
                if (int256(signedCoefficient % 1e5) == 0) {
                    return (signedCoefficient / 1e5, exponent + 5);
                }
                return (signedCoefficient / 1e4, exponent + 4);
            }

            if (int256(signedCoefficient % 1e2) == 0) {
                if (int256(signedCoefficient % 1e3) == 0) {
                    return (signedCoefficient / 1e3, exponent + 3);
                }
                return (signedCoefficient / 1e2, exponent + 2);
            }

            if (int256(signedCoefficient % 1e1) == 0) {
                return (signedCoefficient / 1e1, exponent + 1);
            }

            return (signedCoefficient, exponent);
        }
    }

    // function exp_2(int128 x) internal pure returns (int128) {
    //     unchecked {
    //         require(x < 0x400000000000000000); // Overflow

    //         if (x < -0x400000000000000000) return 0; // Underflow

    //         uint256 result = 0x80000000000000000000000000000000;

    //         if (x & 0x8000000000000000 > 0) {
    //             result = result * 0x16A09E667F3BCC908B2FB1366EA957D3E >> 128;
    //         }
    //         if (x & 0x4000000000000000 > 0) {
    //             result = result * 0x1306FE0A31B7152DE8D5A46305C85EDEC >> 128;
    //         }
    //         if (x & 0x2000000000000000 > 0) {
    //             result = result * 0x1172B83C7D517ADCDF7C8C50EB14A791F >> 128;
    //         }
    //         if (x & 0x1000000000000000 > 0) {
    //             result = result * 0x10B5586CF9890F6298B92B71842A98363 >> 128;
    //         }
    //         if (x & 0x800000000000000 > 0) {
    //             result = result * 0x1059B0D31585743AE7C548EB68CA417FD >> 128;
    //         }
    //         if (x & 0x400000000000000 > 0) {
    //             result = result * 0x102C9A3E778060EE6F7CACA4F7A29BDE8 >> 128;
    //         }
    //         if (x & 0x200000000000000 > 0) {
    //             result = result * 0x10163DA9FB33356D84A66AE336DCDFA3F >> 128;
    //         }
    //         if (x & 0x100000000000000 > 0) {
    //             result = result * 0x100B1AFA5ABCBED6129AB13EC11DC9543 >> 128;
    //         }
    //         if (x & 0x80000000000000 > 0) {
    //             result = result * 0x10058C86DA1C09EA1FF19D294CF2F679B >> 128;
    //         }
    //         if (x & 0x40000000000000 > 0) {
    //             result = result * 0x1002C605E2E8CEC506D21BFC89A23A00F >> 128;
    //         }
    //         if (x & 0x20000000000000 > 0) {
    //             result = result * 0x100162F3904051FA128BCA9C55C31E5DF >> 128;
    //         }
    //         if (x & 0x10000000000000 > 0) {
    //             result = result * 0x1000B175EFFDC76BA38E31671CA939725 >> 128;
    //         }
    //         if (x & 0x8000000000000 > 0) {
    //             result = result * 0x100058BA01FB9F96D6CACD4B180917C3D >> 128;
    //         }
    //         if (x & 0x4000000000000 > 0) {
    //             result = result * 0x10002C5CC37DA9491D0985C348C68E7B3 >> 128;
    //         }
    //         if (x & 0x2000000000000 > 0) {
    //             result = result * 0x1000162E525EE054754457D5995292026 >> 128;
    //         }
    //         if (x & 0x1000000000000 > 0) {
    //             result = result * 0x10000B17255775C040618BF4A4ADE83FC >> 128;
    //         }
    //         if (x & 0x800000000000 > 0) {
    //             result = result * 0x1000058B91B5BC9AE2EED81E9B7D4CFAB >> 128;
    //         }
    //         if (x & 0x400000000000 > 0) {
    //             result = result * 0x100002C5C89D5EC6CA4D7C8ACC017B7C9 >> 128;
    //         }
    //         if (x & 0x200000000000 > 0) {
    //             result = result * 0x10000162E43F4F831060E02D839A9D16D >> 128;
    //         }
    //         if (x & 0x100000000000 > 0) {
    //             result = result * 0x100000B1721BCFC99D9F890EA06911763 >> 128;
    //         }
    //         if (x & 0x80000000000 > 0) {
    //             result = result * 0x10000058B90CF1E6D97F9CA14DBCC1628 >> 128;
    //         }
    //         if (x & 0x40000000000 > 0) {
    //             result = result * 0x1000002C5C863B73F016468F6BAC5CA2B >> 128;
    //         }
    //         if (x & 0x20000000000 > 0) {
    //             result = result * 0x100000162E430E5A18F6119E3C02282A5 >> 128;
    //         }
    //         if (x & 0x10000000000 > 0) {
    //             result = result * 0x1000000B1721835514B86E6D96EFD1BFE >> 128;
    //         }
    //         if (x & 0x8000000000 > 0) {
    //             result = result * 0x100000058B90C0B48C6BE5DF846C5B2EF >> 128;
    //         }
    //         if (x & 0x4000000000 > 0) {
    //             result = result * 0x10000002C5C8601CC6B9E94213C72737A >> 128;
    //         }
    //         if (x & 0x2000000000 > 0) {
    //             result = result * 0x1000000162E42FFF037DF38AA2B219F06 >> 128;
    //         }
    //         if (x & 0x1000000000 > 0) {
    //             result = result * 0x10000000B17217FBA9C739AA5819F44F9 >> 128;
    //         }
    //         if (x & 0x800000000 > 0) {
    //             result = result * 0x1000000058B90BFCDEE5ACD3C1CEDC823 >> 128;
    //         }
    //         if (x & 0x400000000 > 0) {
    //             result = result * 0x100000002C5C85FE31F35A6A30DA1BE50 >> 128;
    //         }
    //         if (x & 0x200000000 > 0) {
    //             result = result * 0x10000000162E42FF0999CE3541B9FFFCF >> 128;
    //         }
    //         if (x & 0x100000000 > 0) {
    //             result = result * 0x100000000B17217F80F4EF5AADDA45554 >> 128;
    //         }
    //         if (x & 0x80000000 > 0) {
    //             result = result * 0x10000000058B90BFBF8479BD5A81B51AD >> 128;
    //         }
    //         if (x & 0x40000000 > 0) {
    //             result = result * 0x1000000002C5C85FDF84BD62AE30A74CC >> 128;
    //         }
    //         if (x & 0x20000000 > 0) {
    //             result = result * 0x100000000162E42FEFB2FED257559BDAA >> 128;
    //         }
    //         if (x & 0x10000000 > 0) {
    //             result = result * 0x1000000000B17217F7D5A7716BBA4A9AE >> 128;
    //         }
    //         if (x & 0x8000000 > 0) {
    //             result = result * 0x100000000058B90BFBE9DDBAC5E109CCE >> 128;
    //         }
    //         if (x & 0x4000000 > 0) {
    //             result = result * 0x10000000002C5C85FDF4B15DE6F17EB0D >> 128;
    //         }
    //         if (x & 0x2000000 > 0) {
    //             result = result * 0x1000000000162E42FEFA494F1478FDE05 >> 128;
    //         }
    //         if (x & 0x1000000 > 0) {
    //             result = result * 0x10000000000B17217F7D20CF927C8E94C >> 128;
    //         }
    //         if (x & 0x800000 > 0) {
    //             result = result * 0x1000000000058B90BFBE8F71CB4E4B33D >> 128;
    //         }
    //         if (x & 0x400000 > 0) {
    //             result = result * 0x100000000002C5C85FDF477B662B26945 >> 128;
    //         }
    //         if (x & 0x200000 > 0) {
    //             result = result * 0x10000000000162E42FEFA3AE53369388C >> 128;
    //         }
    //         if (x & 0x100000 > 0) {
    //             result = result * 0x100000000000B17217F7D1D351A389D40 >> 128;
    //         }
    //         if (x & 0x80000 > 0) {
    //             result = result * 0x10000000000058B90BFBE8E8B2D3D4EDE >> 128;
    //         }
    //         if (x & 0x40000 > 0) {
    //             result = result * 0x1000000000002C5C85FDF4741BEA6E77E >> 128;
    //         }
    //         if (x & 0x20000 > 0) {
    //             result = result * 0x100000000000162E42FEFA39FE95583C2 >> 128;
    //         }
    //         if (x & 0x10000 > 0) {
    //             result = result * 0x1000000000000B17217F7D1CFB72B45E1 >> 128;
    //         }
    //         if (x & 0x8000 > 0) {
    //             result = result * 0x100000000000058B90BFBE8E7CC35C3F0 >> 128;
    //         }
    //         if (x & 0x4000 > 0) {
    //             result = result * 0x10000000000002C5C85FDF473E242EA38 >> 128;
    //         }
    //         if (x & 0x2000 > 0) {
    //             result = result * 0x1000000000000162E42FEFA39F02B772C >> 128;
    //         }
    //         if (x & 0x1000 > 0) {
    //             result = result * 0x10000000000000B17217F7D1CF7D83C1A >> 128;
    //         }
    //         if (x & 0x800 > 0) {
    //             result = result * 0x1000000000000058B90BFBE8E7BDCBE2E >> 128;
    //         }
    //         if (x & 0x400 > 0) {
    //             result = result * 0x100000000000002C5C85FDF473DEA871F >> 128;
    //         }
    //         if (x & 0x200 > 0) {
    //             result = result * 0x10000000000000162E42FEFA39EF44D91 >> 128;
    //         }
    //         if (x & 0x100 > 0) {
    //             result = result * 0x100000000000000B17217F7D1CF79E949 >> 128;
    //         }
    //         if (x & 0x80 > 0) {
    //             result = result * 0x10000000000000058B90BFBE8E7BCE544 >> 128;
    //         }
    //         if (x & 0x40 > 0) {
    //             result = result * 0x1000000000000002C5C85FDF473DE6ECA >> 128;
    //         }
    //         if (x & 0x20 > 0) {
    //             result = result * 0x100000000000000162E42FEFA39EF366F >> 128;
    //         }
    //         if (x & 0x10 > 0) {
    //             result = result * 0x1000000000000000B17217F7D1CF79AFA >> 128;
    //         }
    //         if (x & 0x8 > 0) {
    //             result = result * 0x100000000000000058B90BFBE8E7BCD6D >> 128;
    //         }
    //         if (x & 0x4 > 0) {
    //             result = result * 0x10000000000000002C5C85FDF473DE6B2 >> 128;
    //         }
    //         if (x & 0x2 > 0) {
    //             result = result * 0x1000000000000000162E42FEFA39EF358 >> 128;
    //         }
    //         if (x & 0x1 > 0) {
    //             result = result * 0x10000000000000000B17217F7D1CF79AB >> 128;
    //         }

    //         result >>= uint256(int256(63 - (x >> 64)));
    //         // require(result <= uint256(int256(0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)));

    //         return int128(int256(result));
    //     }
    // }

    function exp22(int128 x) internal pure returns (int128) {
        unchecked {
            require(x < 0x400000000000000000); // Overflow

            if (x < -0x400000000000000000) return 0; // Underflow

            bytes memory table = hex"0000000000000000000000000000000001" hex"016A09E667F3BCC908B2FB1366EA957D3E"
                hex"01306FE0A31B7152DE8D5A46305C85EDEC" hex"01172B83C7D517ADCDF7C8C50EB14A791F"
                hex"010B5586CF9890F6298B92B71842A98363" hex"01059B0D31585743AE7C548EB68CA417FD"
                hex"0102C9A3E778060EE6F7CACA4F7A29BDE8" hex"010163DA9FB33356D84A66AE336DCDFA3F"
                hex"0100B1AFA5ABCBED6129AB13EC11DC9543" hex"010058C86DA1C09EA1FF19D294CF2F679B"
                hex"01002C605E2E8CEC506D21BFC89A23A00F" hex"0100162F3904051FA128BCA9C55C31E5DF"
                hex"01000B175EFFDC76BA38E31671CA939725" hex"0100058BA01FB9F96D6CACD4B180917C3D"
                hex"010002C5CC37DA9491D0985C348C68E7B3" hex"01000162E525EE054754457D5995292026"
                hex"010000B17255775C040618BF4A4ADE83FC" hex"01000058B91B5BC9AE2EED81E9B7D4CFAB"
                hex"0100002C5C89D5EC6CA4D7C8ACC017B7C9" hex"010000162E43F4F831060E02D839A9D16D"
                hex"0100000B1721BCFC99D9F890EA06911763" hex"010000058B90CF1E6D97F9CA14DBCC1628"
                hex"01000002C5C863B73F016468F6BAC5CA2B" hex"0100000162E430E5A18F6119E3C02282A5"
                hex"01000000B1721835514B86E6D96EFD1BFE" hex"0100000058B90C0B48C6BE5DF846C5B2EF"
                hex"010000002C5C8601CC6B9E94213C72737A" hex"01000000162E42FFF037DF38AA2B219F06"
                hex"010000000B17217FBA9C739AA5819F44F9" hex"01000000058B90BFCDEE5ACD3C1CEDC823"
                hex"0100000002C5C85FE31F35A6A30DA1BE50" hex"010000000162E42FF0999CE3541B9FFFCF"
                hex"0100000000B17217F80F4EF5AADDA45554" hex"010000000058B90BFBF8479BD5A81B51AD"
                hex"01000000002C5C85FDF84BD62AE30A74CC" hex"0100000000162E42FEFB2FED257559BDAA"
                hex"01000000000B17217F7D5A7716BBA4A9AE" hex"0100000000058B90BFBE9DDBAC5E109CCE"
                hex"010000000002C5C85FDF4B15DE6F17EB0D" hex"01000000000162E42FEFA494F1478FDE05"
                hex"010000000000B17217F7D20CF927C8E94C" hex"01000000000058B90BFBE8F71CB4E4B33D"
                hex"0100000000002C5C85FDF477B662B26945" hex"010000000000162E42FEFA3AE53369388C"
                hex"0100000000000B17217F7D1D351A389D40" hex"010000000000058B90BFBE8E8B2D3D4EDE"
                hex"01000000000002C5C85FDF4741BEA6E77E" hex"0100000000000162E42FEFA39FE95583C2"
                hex"01000000000000B17217F7D1CFB72B45E1" hex"0100000000000058B90BFBE8E7CC35C3F0"
                hex"010000000000002C5C85FDF473E242EA38" hex"01000000000000162E42FEFA39F02B772C"
                hex"010000000000000B17217F7D1CF7D83C1A" hex"01000000000000058B90BFBE8E7BDCBE2E"
                hex"0100000000000002C5C85FDF473DEA871F" hex"010000000000000162E42FEFA39EF44D91"
                hex"0100000000000000B17217F7D1CF79E949" hex"010000000000000058B90BFBE8E7BCE544"
                hex"01000000000000002C5C85FDF473DE6ECA" hex"0100000000000000162E42FEFA39EF366F"
                hex"01000000000000000B17217F7D1CF79AFA" hex"0100000000000000058B90BFBE8E7BCD6D"
                hex"010000000000000002C5C85FDF473DE6B2" hex"01000000000000000162E42FEFA39EF358"
                hex"010000000000000000B17217F7D1CF79AB";

            uint256 result = 0x80000000000000000000000000000000;

            assembly ("memory-safe") {
                let tableStart := add(table, 0x20)
                let i := and(shr(63, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(62, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(61, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(60, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(59, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(58, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(57, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(56, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(55, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(54, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(53, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(52, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(51, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(50, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(49, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(48, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(47, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(46, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(45, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(44, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(43, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(42, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(41, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(40, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(39, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(38, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(37, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(36, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(35, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(34, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(33, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(32, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(31, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(30, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(29, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(28, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(27, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(26, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(25, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(24, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(23, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(22, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(21, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(20, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(19, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(18, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(17, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(16, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(15, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(14, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(13, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(12, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(11, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(10, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(9, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(8, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(7, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(6, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(5, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(4, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(3, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(2, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(shr(1, x), 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
                i := and(x, 1)
                result := shr(mul(i, 128), mul(result, shr(120, mload(add(tableStart, mul(i, 17))))))
            }

            result >>= uint256(int256(63 - (x >> 64)));
            // require(result <= uint256(int256(0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)));

            return int128(int256(result));
        }
    }
}
