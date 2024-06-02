// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

error SignOverflow(uint256 badSign);
error ExponentOverflow(int256 badExponent);
error CoefficientOverflow(uint256 badCoefficient);

error NegativeFixedDecimalConversion(DecimalFloat value);

type DecimalFloat is uint256;

/// @dev Currently we limit the coefficient bits to 128 so that operations like
/// multiplication can be done with 256 bit integers and be guaranteed not to
/// overflow.
uint256 constant COEFFICIENT_BITS = 128;
uint256 constant COEFFICIENT_MASK = type(uint128).max;

uint256 constant EXPONENT_BITS = 16;
uint256 constant EXPONENT_MASK = type(uint16).max;

library LibDecimalFloat {
    function fromFixedDecimal(uint256 value, uint8 decimals) internal pure returns (DecimalFloat) {
        unchecked {
            return fromParts(0, value, int256(uint256(decimals)) * -1);
        }
    }

    function toFixedDecimal(DecimalFloat value, uint8 decimals) internal pure returns (uint256) {
        unchecked {
            (uint256 sign, uint256 coefficient, int256 exponent) = toParts(value);
            if (sign == 1) {
                revert NegativeFixedDecimalConversion(value);
            }
            return coefficient / (10 ** uint256(int256(uint256(decimals)) + exponent));
        }
    }

    function fromParts(uint256 sign, uint256 coefficient, int256 exponent) internal pure returns (DecimalFloat) {
        if (sign > 1) {
            revert SignOverflow(sign);
        }
        if (exponent < type(int16).min || exponent > type(int16).max) {
            revert ExponentOverflow(exponent);
        }
        if (coefficient > COEFFICIENT_MASK) {
            revert CoefficientOverflow(coefficient);
        }

        DecimalFloat value;
        uint256 exponentMask = EXPONENT_MASK;
        assembly ("memory-safe") {
            // Exponent is signed so we have to zero out the top bits.
            exponent := and(exponent, exponentMask)
            value := or(coefficient, shl(0xEF, exponent))
            value := or(value, shl(0xFF, sign))
        }
        return value;
    }

    function toParts(DecimalFloat value) internal pure returns (uint256 sign, uint256 coefficient, int256 exponent) {
        uint256 coefficientMask = COEFFICIENT_MASK;
        assembly ("memory-safe") {
            sign := shr(0xFF, value)
            coefficient := and(value, coefficientMask)
            exponent := sar(0xF0, shl(1, value))
        }
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
        uint256 coefficient;
        uint256 sign;

        (uint256 signA, uint256 coefficientA, int256 exponentA) = toParts(a);
        (uint256 signB, uint256 coefficientB, int256 exponentB) = toParts(b);

        // Align the exponents.
        if (exponentA == exponentB) {
            // This is likely so short circuit it.
        }
        else if (exponentA > exponentB) {
            coefficientA *= 10 ** uint256(exponentA - exponentB);
            exponentA = exponentB;
        } else {
            coefficientB *= 10 ** uint256(exponentB - exponentA);
            exponentB = exponentA;
        }

        // None of this can overflow because the coefficient is 128 bits.
        // Worst case scenario is that type(uint128).max was aligned all the way
        // to fill the high bits of a 256 bit integer, then we add it to another
        // type(uint128).max, which is exactly type(uint256).max, so no overflow.
        unchecked {
            if (signA == signB) {
                coefficient = coefficientA + coefficientB;
                sign = signA;
            } else if (coefficientA == coefficientB) {
                coefficient = 0;
                // Never produce negative zero.
                sign = 0;
            }
            else if (coefficientA > coefficientB) {
                coefficient = coefficientA - coefficientB;
                sign = signA;
            } else {
                coefficient = coefficientB - coefficientA;
                sign = signB;
            }
        }

        (coefficient, exponent) = normalize(coefficient, exponent);

        return fromParts(sign, coefficient, exponent);
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
        return DecimalFloat.wrap(DecimalFloat.unwrap(value) ^ (1 << 0xFF));
    }

    /// https://speleotrove.com/decimal/daops.html#refabs
    /// > abs takes one operand. If the operand is negative, the result is the
    /// > same as using the minus operation on the operand. Otherwise, the result
    /// > is the same as using the plus operation on the operand.
    function abs(DecimalFloat value) internal pure returns (DecimalFloat) {
        (, uint256 coefficient, int256 exponent) = toParts(value);
        return fromParts(0, coefficient, exponent);
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
        (uint256 signA, uint256 coefficientA, int256 exponentA) = toParts(a);
        (uint256 signB, uint256 coefficientB, int256 exponentB) = toParts(b);

        // We don't support negative zero.
        if (signA != signB) {
            return signA == 1 ? NEG_ONE : ONE;
        }

    }



    function normalize(uint256 coefficient, int256 exponent) internal pure returns (uint256, int256) {
        unchecked {
            while (coefficient > COEFFICIENT_MASK) {
                coefficient /= 10;
                exponent += 1;
            }
            return (coefficient, exponent);
        }
    }
}
