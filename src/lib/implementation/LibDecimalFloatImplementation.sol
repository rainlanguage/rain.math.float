// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    ExponentOverflow,
    Log10Negative,
    Log10Zero,
    MulDivOverflow,
    DivisionByZero,
    MaximizeOverflow,
    Log10RatioRelativeSumTooSmall
} from "../../error/ErrDecimalFloat.sol";

/// @dev Thrown when attempting to rescale a coefficient to a target exponent
error WithTargetExponentOverflow(int256 signedCoefficient, int256 exponent, int256 targetExponent);

/// @dev The maximum difference in exponents when adding to rescale.
uint256 constant ADD_MAX_EXPONENT_DIFF = 76;

/// @dev The maximum exponent that can be maximized.
/// This is crazy large, so should never be a problem for any real use case.
/// We need it to guard against overflow when maximizing.
int256 constant EXPONENT_MAX = type(int256).max / 2;

/// @dev The minimum exponent that can be maximized.
/// This is crazy small, so should never be a problem for any real use case.
/// We need it to guard against overflow when maximized.
int256 constant EXPONENT_MIN = -EXPONENT_MAX;

/// @dev The signed coefficient of maximized zero.
int256 constant MAXIMIZED_ZERO_SIGNED_COEFFICIENT = 0;

/// @dev The exponent of maximized zero.
int256 constant MAXIMIZED_ZERO_EXPONENT = 0;

/// @dev Fixed point one for the log10 and pow10 series.
uint256 constant POW_FIXED_ONE = 1e50;

/// @dev ln(10) at the `POW_FIXED_ONE` scale, rounded down, 0.2976 units below,
/// which is also nearest.
uint256 constant POW_FIXED_LN10 = 230258509299404568401799145468436420760110148862877;

/// @dev The inverse of 5^50 modulo 2^256, which divides a multiple of
/// `POW_FIXED_ONE` by it once the factor 2^50 is shifted out.
uint256 constant POW_FIXED_ONE_ODD_INVERSE =
    32019276099673541610834237427944372346803171054071557274126404137164986125033;

/// @dev The inverse of 5 modulo 2^256, so that its nth power divides an exact
/// multiple of 5^n.
uint256 constant FIVE_INVERSE = 92633671389852956338856788006950326282615987732512451231566067206330503711949;

/// @dev Guard digits pow10 rounds away.
uint256 constant POW_GUARD = 1e10;

/// @dev The most, in units of 1e-50, that the true 10^m 1e50 can lie from
/// pow10's fixed point power. See `pow10`.
uint256 constant POW10_RAW_ERROR = 328;

/// @dev The most, in units of 1e-50, that the true log can lie from
/// `log10Unrounded`. See `log10Unrounded`.
uint256 constant LOG10_RAW_ERROR = 2;

/// @dev Library implementing core DecimalFloat operations using only stack
/// variables.
/// NOT intended for external use, typical use is to treat the `Float` type
/// as the interface to the float functionality. The tradeoff is better
/// abstractions for some more gas and less range of the operations due to
/// packing and unpacking having fundamental bit size limitations.
library LibDecimalFloatImplementation {
    /// Negates a float.
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

    /// Returns the absolute value of a signed coefficient as an unsigned
    /// integer.
    /// @param signedCoefficient The signed coefficient.
    /// @return The absolute value as an unsigned integer.
    function absUnsignedSignedCoefficient(int256 signedCoefficient) internal pure returns (uint256) {
        unchecked {
            if (signedCoefficient < 0) {
                if (signedCoefficient == type(int256).min) {
                    return uint256(type(int256).max) + 1;
                } else {
                    // signedCoefficient < 0
                    // forge-lint: disable-next-line(unsafe-typecast)
                    return uint256(-signedCoefficient);
                }
            } else {
                // signedCoefficient >= 0
                // forge-lint: disable-next-line(unsafe-typecast)
                return uint256(signedCoefficient);
            }
        }
    }

    /// Given the absolute value of the result coefficient, and the signs of
    /// the input coefficients, returns the signed coefficient and exponent of
    /// the result of a multiplication or division operation.
    /// @param a The signed coefficient of the first operand.
    /// @param b The signed coefficient of the second operand.
    /// @param signedCoefficientAbs The absolute value of the result coefficient.
    /// @param exponent The exponent of the result.
    /// @return signedCoefficient The signed coefficient of the result.
    /// @return exponent The exponent of the result.
    function unabsUnsignedMulOrDivLossy(int256 a, int256 b, uint256 signedCoefficientAbs, int256 exponent)
        internal
        pure
        returns (int256, int256)
    {
        // Need to minus the coefficient because a and b had different signs.
        if ((a ^ b) < 0) {
            if (signedCoefficientAbs > uint256(type(int256).max)) {
                if (signedCoefficientAbs == uint256(type(int256).max) + 1) {
                    // Edge case where the absolute value is exactly
                    // type(int256).min.
                    return (type(int256).min, exponent);
                } else {
                    // signedCoefficientAbs divided by 10 so won't truncate when
                    // cast.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    return (-int256(signedCoefficientAbs / 10), exponent + 1);
                }
            } else {
                // signedCoefficientAbs [0, type(int256).max]
                // forge-lint: disable-next-line(unsafe-typecast)
                return (-int256(signedCoefficientAbs), exponent);
            }
        } else {
            if (signedCoefficientAbs > uint256(type(int256).max)) {
                // signedCoefficientAbs divided by 10 so won't truncate when
                // cast.
                // forge-lint: disable-next-line(unsafe-typecast)
                return (int256(signedCoefficientAbs / 10), exponent + 1);
            } else {
                // signedCoefficientAbs is bound to the int256 range.
                // forge-lint: disable-next-line(unsafe-typecast)
                return (int256(signedCoefficientAbs), exponent);
            }
        }
    }

    /// Stack only implementation of `mul`.
    /// @param signedCoefficientA The signed coefficient of the first operand.
    /// @param exponentA The exponent of the first operand.
    /// @param signedCoefficientB The signed coefficient of the second operand.
    /// @param exponentB The exponent of the second operand.
    /// @return signedCoefficient The signed coefficient of the result.
    /// @return exponent The exponent of the result.
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
            unchecked {
                exponent = exponentA + exponentB;
            }
            // Both exponents in [-2^253, 2^253) cannot wrap the sum or reach
            // the ceiling margin below, so packed operands pay one branch.
            bool isWide;
            assembly ("memory-safe") {
                isWide := shr(254, or(add(exponentA, shl(253, 1)), add(exponentB, shl(253, 1))))
            }
            if (isWide) {
                if (exponentB < 0) {
                    if (exponent > exponentA) {
                        return mulExponentBelowFloor(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
                    }
                } else if (exponent < exponentA) {
                    return mulExponentNearCeiling(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
                }
                // The lift below adds at most 77 and
                // `unabsUnsignedMulOrDivLossy` at most 1.
                if (exponent > type(int256).max - 78) {
                    return mulExponentNearCeiling(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
                }
            }

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

                // adjustExponent [0, 77]
                // forge-lint: disable-next-line(unsafe-typecast)
                exponent += int256(adjustExponent);
            }

            (signedCoefficient, exponent) = unabsUnsignedMulOrDivLossy(
                signedCoefficientA,
                signedCoefficientB,
                mulDivPow10(signedCoefficientAAbs, signedCoefficientBAbs, adjustExponent),
                exponent
            );
        }
    }

    /// `mul` for operands whose exponent sum is below `type(int256).min`. The
    /// product is taken with each exponent 2^254 higher, then moved back down,
    /// shedding the digits that do not fit above the floor.
    function mulExponentBelowFloor(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) private pure returns (int256 signedCoefficient, int256 exponent) {
        unchecked {
            int256 shift = 2 ** 254;
            (signedCoefficient, exponent) =
                mul(signedCoefficientA, exponentA + shift, signedCoefficientB, exponentB + shift);
            if (exponent >= 0) {
                return (signedCoefficient, exponent + type(int256).min);
            }
            if (exponent < -76) {
                return (MAXIMIZED_ZERO_SIGNED_COEFFICIENT, MAXIMIZED_ZERO_EXPONENT);
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            signedCoefficient /= int256(10 ** uint256(-exponent));
            exponent = signedCoefficient == 0 ? MAXIMIZED_ZERO_EXPONENT : type(int256).min;
        }
    }

    /// `mul` for operands whose exponent sum is above `type(int256).max - 78`,
    /// where the normalisation can lift the exponent past `type(int256).max`.
    /// Reverts `ExponentOverflow` when the result exponent does not fit.
    function mulExponentNearCeiling(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) private pure returns (int256 signedCoefficient, int256 exponent) {
        (signedCoefficient, exponent) = mul(signedCoefficientA, 0, signedCoefficientB, 0);
        unchecked {
            int256 sum = exponentA + exponentB;
            int256 result = sum + exponent;
            if ((exponentB >= 0 && sum < exponentA) || result < sum) {
                revert ExponentOverflow(signedCoefficientA, exponentA);
            }
            exponent = result;
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
    /// @param signedCoefficientA The signed coefficient of the dividend.
    /// @param exponentA The exponent of the dividend.
    /// @param signedCoefficientB The signed coefficient of the divisor.
    /// @param exponentB The exponent of the divisor.
    /// @return signedCoefficient The signed coefficient of the quotient.
    /// @return exponent The exponent of the quotient.
    //slither-disable-next-line cyclomatic-complexity
    function div(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
        if (signedCoefficientB == 0) {
            revert DivisionByZero(signedCoefficientA, exponentA);
        } else if (signedCoefficientA == 0) {
            return (MAXIMIZED_ZERO_SIGNED_COEFFICIENT, MAXIMIZED_ZERO_EXPONENT);
        } else {
            int256 signedCoefficient;
            int256 exponent;
            int256 shortfallA;
            int256 shortfallB;
            // Move both coefficients into the e75/e76 range, so that the result
            // of division will not cause a mulDiv overflow.
            (signedCoefficientA, exponentA, shortfallA) = maximize(signedCoefficientA, exponentA);
            (signedCoefficientB, exponentB, shortfallB) = maximize(signedCoefficientB, exponentB);

            // mulDiv only works with unsigned integers, so get the absolute
            // values of the coefficients.
            uint256 signedCoefficientAAbs = absUnsignedSignedCoefficient(signedCoefficientA);
            uint256 signedCoefficientBAbs = absUnsignedSignedCoefficient(signedCoefficientB);

            // We are going to scale the numerator up by the largest power of ten
            // that is not larger than the denominator. This will always overflow
            // internally to the mulDiv during the initial multiplication, in
            // 512 bits, but will subsequently always be reduced back down to
            // fit in 256 bits by the division of a denominator that is not
            // smaller than the scale up.
            uint256 scale = 1e76;
            int256 adjustExponent = 76;
            if (signedCoefficientBAbs < scale) {
                scale = 1e75;
                adjustExponent = 75;
            }
            // The shortfalls are the digits each exponent sits above its true
            // value. The divisor's shortfall never exceeds the scale's digits,
            // so the adjustment stays non-negative.
            unchecked {
                adjustExponent += shortfallA - shortfallB;
            }

            // Attempt to apply the exponent adjustment.
            // First we try to apply it to exponentA.
            // If we cannot fully apply it we try to apply the rest to exponentB.
            // If we still have some left over then we just return zero as
            // the difference in exponents is too large to represent in
            // a single result negative exponent.
            unchecked {
                if (exponentA >= type(int256).min + adjustExponent) {
                    exponentA -= adjustExponent;
                } else {
                    adjustExponent -= exponentA - type(int256).min;
                    exponentA = type(int256).min;

                    if (adjustExponent > 0) {
                        if (exponentB <= type(int256).max - adjustExponent) {
                            exponentB += adjustExponent;
                        } else {
                            return (MAXIMIZED_ZERO_SIGNED_COEFFICIENT, MAXIMIZED_ZERO_EXPONENT);
                        }
                    }
                }
            }

            int256 underflowExponentBy = 0;

            unchecked {
                // This is the only case that can underflow.
                if (exponentA < 0 && exponentB > 0) {
                    int256 headroom = exponentA - type(int256).min;
                    underflowExponentBy = exponentB > headroom ? exponentB - headroom : int256(0);
                }

                if (exponentB < 0 && exponentA > type(int256).max + exponentB) {
                    revert ExponentOverflow(signedCoefficientA, exponentA);
                }

                exponent = exponentA + underflowExponentBy - exponentB;

                // The quotient only exceeds type(int256).max as 2^255, from
                // type(int256).min over the scale. Positive, it sheds a digit
                // into the exponent.
                if (
                    exponent == type(int256).max && signedCoefficientA == type(int256).min
                        && signedCoefficientBAbs == scale && signedCoefficientB < 0
                ) {
                    revert ExponentOverflow(signedCoefficientA, exponentA);
                }

                (signedCoefficient, exponent) = unabsUnsignedMulOrDivLossy(
                    signedCoefficientA,
                    signedCoefficientB,
                    mulDiv(signedCoefficientAAbs, scale, signedCoefficientBAbs),
                    exponent
                );

                if (underflowExponentBy > 0) {
                    if (underflowExponentBy > 76) {
                        // This means the exponent is too small to represent even if
                        // we truncate and downscale the signed coefficient.
                        return (MAXIMIZED_ZERO_SIGNED_COEFFICIENT, MAXIMIZED_ZERO_EXPONENT);
                    }

                    // underflowExponentBy [1, 76]
                    // forge-lint: disable-next-line(unsafe-typecast)
                    signedCoefficient /= int256(10 ** uint256(underflowExponentBy));
                    if (signedCoefficient == 0) {
                        exponent = MAXIMIZED_ZERO_EXPONENT;
                    }
                }
                return (signedCoefficient, exponent);
            }
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

    /// mulDiv(x, y, POW_FIXED_ONE) for a quotient below 2^256.
    function mulDivFixed(uint256 x, uint256 y) internal pure returns (uint256 result) {
        uint256 inverse = POW_FIXED_ONE_ODD_INVERSE;
        assembly ("memory-safe") {
            let mm := mulmod(x, y, not(0))
            let prod0 := mul(x, y)
            // slither-disable-next-line too-many-digits
            let remainder := mulmod(x, y, 100000000000000000000000000000000000000000000000000)
            let prod1 := sub(sub(sub(mm, prod0), lt(mm, prod0)), gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
            result := mul(or(shr(50, prod0), shl(206, prod1)), inverse)
        }
    }

    /// mulDiv(x, y, 10^n) for n in [0, 76] and a quotient below 2^256. The
    /// remainder is subtracted so 10^n divides the product exactly, the 2^n
    /// is shifted out and the 5^n divided out by its inverse modulo 2^256.
    function mulDivPow10(uint256 x, uint256 y, uint256 n) internal pure returns (uint256 result) {
        (uint256 prod1, uint256 prod0) = mul512(x, y);
        if (prod1 == 0) {
            unchecked {
                return prod0 / 10 ** n;
            }
        }
        uint256 inverse = FIVE_INVERSE;
        assembly ("memory-safe") {
            let remainder := mulmod(x, y, exp(10, n))
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
            result := mul(or(shr(n, prod0), shl(sub(256, n), prod1)), exp(inverse, n))
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
    /// Aligning truncates the smaller operand towards zero to the larger
    /// operand's int256 unit, so the returned sum is the exact sum rounded to
    /// that unit, or ten of them past int256: towards zero when the signs
    /// agree, and away from zero when they differ. `1e100 + -1` returns
    /// `1e100`. `LibDecimalFloat.add` states the rule with packing.
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
        int256 shortfallA;
        int256 shortfallB;
        (signedCoefficientA, exponentA, shortfallA) = maximize(signedCoefficientA, exponentA);
        (signedCoefficientB, exponentB, shortfallB) = maximize(signedCoefficientB, exponentB);

        // We want A to represent the larger true exponent, which is the
        // exponent less the shortfall. If this is not the case then swap them.
        // A shortfall is only nonzero at the exponent floor, so comparing the
        // shortfalls breaks the tie there.
        if (exponentB > exponentA || shortfallB < shortfallA) {
            int256 tmp = signedCoefficientA;
            signedCoefficientA = signedCoefficientB;
            signedCoefficientB = tmp;

            tmp = exponentA;
            exponentA = exponentB;
            exponentB = tmp;

            tmp = shortfallA;
            shortfallA = shortfallB;
            shortfallB = tmp;
        }

        // After maximization the signed coefficients are the same OOM in
        // magnitude. However, what we need is for the exponents to be the same.
        // If the exponents are close enough we can divide coefficient B by
        // some power of 10 to align their exponents without precision loss.
        // If the exponents are too far apart, then all the information in B
        // would be lost, so we can just ignore B and return A.
        unchecked {
            // exponentA >= exponentB so exponentA - exponentB will fit in
            // uint256.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 alignmentExponentDiff = uint256(exponentA - exponentB);
            // shortfallB >= shortfallA after the swap, and both are at most 76.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 shortfallDiff = uint256(shortfallB - shortfallA);
            // The early return here allows us to do unchecked pow on the
            // scaler and means we never revert due to overflow here. It is only
            // reachable with shortfallA == 0, as a nonzero shortfallA puts both
            // exponents at the floor.
            if (alignmentExponentDiff > ADD_MAX_EXPONENT_DIFF - shortfallDiff) {
                return (signedCoefficientA, exponentA);
            }
            // alignmentExponentDiff + shortfallDiff can't be greater than 76 so
            // will pow without truncation.
            // forge-lint: disable-next-line(unsafe-typecast)
            signedCoefficientB /= int256(10 ** (alignmentExponentDiff + shortfallDiff));
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
                if (type(int256).max == exponentA) {
                    revert ExponentOverflow(signedCoefficientA, exponentA);
                }

                signedCoefficientA /= 10;
                signedCoefficientB /= 10;
                exponentA++;
                signedCoefficientA += signedCoefficientB;
            } else {
                signedCoefficientA = c;
            }

            // The sum's true exponent is below the floor, so shed the digits
            // the floor cannot hold. exponentA is the floor, or one above it
            // after an overflow.
            if (shortfallA != 0) {
                // The shed is in [0, 76].
                // forge-lint: disable-next-line(unsafe-typecast)
                signedCoefficientA /= int256(10 ** uint256(shortfallA - (exponentA - type(int256).min)));
                exponentA = type(int256).min;
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
    /// @param signedCoefficient The signed coefficient of the float.
    /// @param exponent The exponent of the float.
    /// @return signedCoefficient The signed coefficient of the inverted float.
    /// @return exponent The exponent of the inverted float.
    function inv(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        return div(1e76, -76, signedCoefficient, exponent);
    }

    /// log10(x) for a float x, rounded to nearest at 41 significant digits,
    /// half away from zero, so within half a unit in the 41st digit plus
    /// `LOG10_RAW_ERROR` units of 1e-50. log10(10^k) is exactly k.
    ///
    /// @param signedCoefficient The signed coefficient of the floating point
    /// number.
    /// @param exponent The exponent of the floating point number.
    /// @return signedCoefficient The signed coefficient of the result.
    /// @return exponent The exponent of the result.
    function log10(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        (signedCoefficient, exponent) = log10Unrounded(signedCoefficient, exponent);
        return roundSignificant(signedCoefficient, exponent);
    }

    /// Rounds a float to 41 significant digits, half away from zero. The
    /// exponent rises by the digits shed and never falls, so it reverts only
    /// `ExponentOverflow` when the rounded exponent passes int256.max.
    /// @param signedCoefficient The signed coefficient of the float.
    /// @param exponent The exponent of the float.
    /// @return signedCoefficient The rounded signed coefficient.
    /// @return exponent The rounded exponent.
    function roundSignificant(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        if (signedCoefficient / 1e41 == 0) {
            return (signedCoefficient, exponent);
        }
        int256 guard = 1;
        int256 shed = 0;
        unchecked {
            // Binary search for the 10^shed that leaves 41 digits, shed in
            // [1, 36] for a coefficient of 42 to 77 digits.
            if (signedCoefficient / 1e72 != 0) {
                guard = 1e32;
                shed = 32;
            }
            if (signedCoefficient / guard / 1e56 != 0) {
                guard *= 1e16;
                shed += 16;
            }
            if (signedCoefficient / guard / 1e48 != 0) {
                guard *= 1e8;
                shed += 8;
            }
            if (signedCoefficient / guard / 1e44 != 0) {
                guard *= 1e4;
                shed += 4;
            }
            if (signedCoefficient / guard / 1e42 != 0) {
                guard *= 1e2;
                shed += 2;
            }
            if (signedCoefficient / guard / 1e41 != 0) {
                guard *= 10;
                shed += 1;
            }
            if (exponent > type(int256).max - shed) {
                revert ExponentOverflow(signedCoefficient, exponent);
            }
            int256 rounded = signedCoefficient / guard;
            int256 remainder = signedCoefficient % guard;
            if (remainder >= guard / 2) {
                rounded += 1;
            } else if (remainder <= -guard / 2) {
                rounded -= 1;
            }
            return (rounded, exponent + shed);
        }
    }

    /// log10(x) for a float x, with the guard digits that `log10` rounds
    /// away.
    ///
    /// `log10Reduce` divides the coefficient C in [1e75, 1e76) by powers
    /// 10^(2^-i) that sum to an exact seed S, leaving R within 10^(2^-16) of
    /// 1e75, and the atanh series of R / 1e75 closes the remaining gap. A
    /// coefficient within a factor 1.001 of a power of ten skips the reduction
    /// and takes S = 0, so a log near zero keeps its relative precision.
    ///
    /// The error, from the bounds on `log10Reduce` and `log10Ratio`, is within
    /// `LOG10_RAW_ERROR` units of 1e-50 for a log below 1e25 in magnitude,
    /// which includes every float:
    /// - Within a factor 1.001 of 1: the result is the relative coefficient
    ///   of `log10Ratio`, at least 4.34e48, so within 3.27e-49 relative of a
    ///   log below log10(1.001), under 1.5e-52.
    /// - Otherwise the result is characteristic + S + log10Ratio at 1e-50. R
    ///   is within 16.7 units of C / 10^S, 1.67e-74 relative, which moves its
    ///   log by under 1e-24 units. With log10Ratio's 1.0043 units the true
    ///   log is within 1.0044 units, which rounds up to 2.
    /// - log10(10^k) is exactly k.
    /// A characteristic of 1e25 or more is summed by `add`, which loses under
    /// a unit of the sum's exponent, at least -50.
    ///
    /// @param signedCoefficient The signed coefficient of the floating point
    /// number.
    /// @param exponent The exponent of the floating point number.
    /// @return signedCoefficient The signed coefficient of the result.
    /// @return exponent The exponent of the result.
    function log10Unrounded(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        if (signedCoefficient <= 0) {
            if (signedCoefficient == 0) {
                revert Log10Zero();
            } else {
                revert Log10Negative(signedCoefficient, exponent);
            }
        }
        int256 shortfall = 0;
        // A coefficient of at least 1e75 is in place. Below it, scaleUp shifts
        // by at most 75 digits, which the exponent takes unless it is within
        // 75 of the floor, where maximize returns the shortfall.
        if (signedCoefficient < 1e75) {
            if (exponent >= type(int256).min + 75) {
                (signedCoefficient, exponent) = scaleUp(signedCoefficient, exponent);
            } else {
                (signedCoefficient, exponent, shortfall) = maximize(signedCoefficient, exponent);
            }
        }

        if (signedCoefficient >= 1e76) {
            signedCoefficient /= 10;
            exponent += 1;
        }
        // The input is the coefficient at 10^(exponent - shortfall), and its
        // log is at least int256.min, so the characteristic cannot overflow.
        int256 characteristic = exponent + 75 - shortfall;
        if (signedCoefficient == 1e75) {
            return (characteristic, 0);
        }

        // log10(estimate / 1e75) = seed / 1e50
        int256 seed = 0;
        uint256 estimate;
        if (signedCoefficient < 1.001e75) {
            estimate = 1e75;
        } else if (signedCoefficient >= 9.999e75) {
            characteristic += 1;
            estimate = 1e76;
        } else {
            estimate = 1e75;
            // signedCoefficient is positive.
            // forge-lint: disable-next-line(unsafe-typecast)
            (uint256 reduced, uint256 reducedSeed) = log10Reduce(uint256(signedCoefficient));
            // Both are below 1e76.
            // forge-lint: disable-next-line(unsafe-typecast)
            (signedCoefficient, seed) = (int256(reduced), int256(reducedSeed));
        }

        // A log near zero is all correction, which keeps its relative
        // precision. Anything else is summed at the 1e50 scale.
        bool relative = characteristic == 0 && seed == 0;
        // signedCoefficient is positive.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 input = uint256(signedCoefficient);
        (int256 correctionCoefficient, int256 correctionExponent) = log10Ratio(input, estimate, relative);
        if (relative) {
            return (correctionCoefficient, correctionExponent);
        }
        correctionCoefficient += seed;
        if (characteristic > -1e25 && characteristic < 1e25) {
            return (characteristic * 1e50 + correctionCoefficient, -50);
        }
        return add(characteristic, 0, correctionCoefficient, -50);
    }

    /// log10(a / b) as a float, by 2 atanh((a - b) / (a + b)) / ln(10), for
    /// a and b within a few parts in ten thousand of each other.
    ///
    /// Error, in units of 1e-50 unless stated, for z = |a - b| / (a + b) at
    /// most 5.1e-4. That holds as a / b is within a factor 1.001 at a power
    /// of ten and within 10^(2^-16) after `log10Reduce`.
    /// - The floored z and z^2 make each power of z^2 at most 2.001 below its
    ///   exact value, then at most 1.000001 once the floor dominates. Each
    ///   term's divide floors a further unit. z^16 is below 1e-50, so the loop
    ///   stops by the eighth power and the floored series is at most 8.4 below
    ///   atanh(z) / z.
    /// - Scaling by 2 / ln 10 floors a unit, and POW_FIXED_LN10 is 0.2976
    ///   below ln 10 1e50, so the scaled series is within (-8.3, 1.3e-51
    ///   relative] of 2 atanh(z) / (z ln 10).
    /// - The last mulDiv multiplies that by z, or by z 10^k when `relative`,
    ///   and floors a unit. Not relative, the result is within 1 + 8.3 z,
    ///   under 1.0043, units of the log. Relative, it is within the coefficient C times 9.6e-50, plus
    ///   a unit, below and 1.3e-51 relative above, so within C / 1e49 + 2
    ///   units of its exponent.
    /// @param a The numerator, at most 1e76.
    /// @param b The denominator, at most 1e76.
    /// @param relative `true` for at least 48 significant digits however small
    /// the log, which needs a + b of at least 1e50 and reverts
    /// `Log10RatioRelativeSumTooSmall` below it, `false` for a coefficient at
    /// the `POW_FIXED_ONE` scale.
    /// @return signedCoefficient The signed coefficient of the log.
    /// @return exponent The exponent of the log.
    function log10Ratio(uint256 a, uint256 b, bool relative) internal pure returns (int256, int256) {
        bool below = a < b;
        uint256 difference = below ? b - a : a - b;
        uint256 sum = a + b;
        uint256 z;
        int256 exponent = -50;
        if (relative) {
            if (sum < POW_FIXED_ONE) {
                revert Log10RatioRelativeSumTooSmall(a, b);
            }
            z = mulDiv(difference, POW_FIXED_ONE, sum);
            // difference is below 1e76 so it fits and maximizes in place.
            // forge-lint: disable-next-line(unsafe-typecast)
            (int256 differenceCoefficient, int256 differenceExponent) = maximizeFull(int256(difference), 0);
            // forge-lint: disable-next-line(unsafe-typecast)
            difference = uint256(differenceCoefficient);
            exponent += differenceExponent;
        } else {
            z = mulDiv(difference, POW_FIXED_ONE, sum);
        }
        uint256 zSquared = mulDivFixed(z, z);
        // atanh(z) / z
        uint256 series = POW_FIXED_ONE;
        uint256 term = POW_FIXED_ONE;
        for (uint256 k = 3; term > 0; k += 2) {
            term = mulDivFixed(term, zSquared);
            series += term / k;
        }
        // The scaled series is below 0.8686e50, so the quotient is below it
        // when not relative, and below int256.max / 1e50 times it when
        // relative, as a + b is at least 1e50.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedCoefficient = int256(mulDiv(difference, mulDiv(series, 2 * POW_FIXED_ONE, POW_FIXED_LN10), sum));
        return (below ? -signedCoefficient : signedCoefficient, exponent);
    }

    /// Scales a coefficient in (0, 1e75) up into [1e75, 1e76), lowering the
    /// exponent by the at most 75 digits of the shift.
    /// @param signedCoefficient The signed coefficient, in (0, 1e75).
    /// @param exponent The exponent, at least `type(int256).min + 75`.
    /// @return signedCoefficient The scaled coefficient.
    /// @return exponent The exponent of the scaled coefficient.
    function scaleUp(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        unchecked {
            if (signedCoefficient < 1e38) {
                signedCoefficient *= 1e38;
                exponent -= 38;
            }
            if (signedCoefficient < 1e57) {
                signedCoefficient *= 1e19;
                exponent -= 19;
            }
            if (signedCoefficient < 1e66) {
                signedCoefficient *= 1e10;
                exponent -= 10;
            }
            if (signedCoefficient < 1e71) {
                signedCoefficient *= 1e5;
                exponent -= 5;
            }
            if (signedCoefficient < 1e73) {
                signedCoefficient *= 1e3;
                exponent -= 3;
            }
            if (signedCoefficient < 1e74) {
                signedCoefficient *= 1e2;
                exponent -= 2;
            }
            if (signedCoefficient < 1e75) {
                signedCoefficient *= 10;
                exponent -= 1;
            }
            return (signedCoefficient, exponent);
        }
    }

    /// The square root of a positive float, rounded to nearest at 41
    /// significant digits. A root is never a midpoint: (2r + 1)^2 is odd and
    /// 4N even.
    ///
    /// With the coefficient C scaled into [1e75, 1e76), N is C 1e5 for an odd
    /// exponent and C 1e6 for an even one, so sqrt N is in [1e40, 1e41) and
    /// its exponent is whole.
    ///
    /// The estimate is 1e3 times the Newton root of C / 10 or C, whose root is
    /// in [2^122.9, 2^126.3): from 2^125, the seventh iterate is within
    /// 4.7e-27 relative above it and at least its floor. So the estimate is
    /// within 4.7e14 of sqrt N, and one Newton step over N lands within 1.2e-11
    /// above sqrt N and at least its floor: on the floor or one above.
    ///
    /// One above the floor, it is within 1.2e-11 of sqrt N, so past the
    /// midpoint below it, and is the rounded root. On the floor r, the root
    /// rounds up exactly when N - r^2 > r. |N - r^2| is at most 2r + 1, far
    /// under 2^255, so the low words of N and r^2 give it signed, though N
    /// passes 2^256, and negative is the case one above.
    /// @param signedCoefficient The coefficient, in (0, 1e76).
    /// @param exponent The exponent, at least `type(int256).min + 81`.
    /// @return signedCoefficient The root's coefficient, in [1e40, 1e41].
    /// @return exponent The root's exponent.
    function sqrt(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        (signedCoefficient, exponent) = scaleUp(signedCoefficient, exponent);
        unchecked {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 coefficient = uint256(signedCoefficient);
            uint256 scale = 1e6;
            uint256 estimate = coefficient;
            if (exponent & 1 == 1) {
                scale = 1e5;
                estimate = coefficient / 10;
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            exponent = (exponent - (scale == 1e5 ? int256(5) : int256(6))) / 2;
            uint256 root;
            assembly ("memory-safe") {
                root := add(shr(126, estimate), shl(124, 1))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
            }
            root *= 1e3;
            root = (root + mulDiv(coefficient, scale, root)) >> 1;
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 residual = int256(coefficient * scale - root * root);
            // forge-lint: disable-next-line(unsafe-typecast)
            if (residual > int256(root)) {
                root += 1;
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            return (int256(root), exponent);
        }
    }

    /// Divides x out by 10^(2^-i) for each i in [1, 16] where x is at least
    /// 1e75 10^(2^-i), each by its reciprocal at the 2^256 scale, so x lands
    /// within a factor 10^(2^-16) of 1e75 and the summed powers are the log
    /// of the factor taken out.
    ///
    /// Each threshold is 1e75 10^(2^-i) rounded up and each reciprocal
    /// 2^256 / 10^(2^-i) rounded to nearest, so a step is within
    /// x / 2^257 < 0.0432 of x / 10^(2^-i) before its floor, in
    /// (-1.0432, 0.0432]. Later steps only shrink an earlier step's error, so
    /// the reduced x is within (-16.7, 0.7] of x / 10^seed. A step leaves x
    /// below the next threshold, so the reduced x is in (1e75 - 1.05,
    /// 1e75 10^(2^-16)).
    /// @param x A value in [1e75, 1e76).
    /// @return The reduced x.
    /// @return seed The summed powers at the `POW_FIXED_ONE` scale.
    // slither-disable-start too-many-digits
    //slither-disable-next-line cyclomatic-complexity
    function log10Reduce(uint256 x) internal pure returns (uint256, uint256 seed) {
        assembly ("memory-safe") {
            if iszero(lt(x, 3162277660168379331998893544432718533719555139325216826857504852792594438640)) {
                let mm :=
                    mulmod(x, 36616673701938843778068833497358723556965087776446405157389940026215161181517, not(0))
                let low := mul(x, 36616673701938843778068833497358723556965087776446405157389940026215161181517)
                x := sub(sub(mm, low), lt(mm, low))
                seed := add(seed, 50000000000000000000000000000000000000000000000000)
            }
            if iszero(lt(x, 1778279410038922801225421195192684844735790526402255358011830722776301881540)) {
                let mm :=
                    mulmod(x, 65114676908271546481783089451486774924122586772716488419433647202158216225712, not(0))
                let low := mul(x, 65114676908271546481783089451486774924122586772716488419433647202158216225712)
                x := sub(sub(mm, low), lt(mm, low))
                seed := add(seed, 25000000000000000000000000000000000000000000000000)
            }
            if iszero(lt(x, 1333521432163324025675931715295331092415667964764370993329549987162758943181)) {
                let mm :=
                    mulmod(x, 86831817205570396472488487376619414734776470364260362375271208847034186727869, not(0))
                let low := mul(x, 86831817205570396472488487376619414734776470364260362375271208847034186727869)
                x := sub(sub(mm, low), lt(mm, low))
                seed := add(seed, 12500000000000000000000000000000000000000000000000)
            }
            if iszero(lt(x, 1154781984689458179666482887295508281566948041479611129977426848717929206981)) {
                let mm :=
                    mulmod(x, 100271818206840824917852211318445810475964718432762174250931870037200512150264, not(0))
                let low := mul(x, 100271818206840824917852211318445810475964718432762174250931870037200512150264)
                x := sub(sub(mm, low), lt(mm, low))
                seed := add(seed, 6250000000000000000000000000000000000000000000000)
            }
            if iszero(lt(x, 1074607828321317497215941531964343594667198228375277635737525385456277680090)) {
                let mm :=
                    mulmod(x, 107752880805083163274215415406366939907498821726554665908884917759802168845149, not(0))
                let low := mul(x, 107752880805083163274215415406366939907498821726554665908884917759802168845149)
                x := sub(sub(mm, low), lt(mm, low))
                seed := add(seed, 3125000000000000000000000000000000000000000000000)
            }
            if iszero(lt(x, 1036632928437697997291651724925344467708873031101004651184732490611638515681)) {
                let mm :=
                    mulmod(x, 111700184376571576959242954511464064493576035854940459532905296431575491590884, not(0))
                let low := mul(x, 111700184376571576959242954511464064493576035854940459532905296431575491590884)
                x := sub(sub(mm, low), lt(mm, low))
                seed := add(seed, 1562500000000000000000000000000000000000000000000)
            }
            if iszero(lt(x, 1018151721718181841474226888578835347615879638667598311831418789512158676639)) {
                let mm :=
                    mulmod(x, 113727735039244707269314004292417912634116897559789282410115004998408115167755, not(0))
                let low := mul(x, 113727735039244707269314004292417912634116897559789282410115004998408115167755)
                x := sub(sub(mm, low), lt(mm, low))
                seed := add(seed, 781250000000000000000000000000000000000000000000)
            }
            if iszero(lt(x, 1009035044841447437759254423906421331381168979588236162503174368256031811568)) {
                let mm :=
                    mulmod(x, 114755270225040536177195215467999502584020270197659510607710463068073932425995, not(0))
                let low := mul(x, 114755270225040536177195215467999502584020270197659510607710463068073932425995)
                x := sub(sub(mm, low), lt(mm, low))
                seed := add(seed, 390625000000000000000000000000000000000000000000)
            }
            if iszero(lt(x, 1004507364254462515664794694341317664136965486448855489880346341316837480908)) {
                let mm :=
                    mulmod(x, 115272514028064070535758128409080922034070970152660607303989700309153489211414, not(0))
                let low := mul(x, 115272514028064070535758128409080922034070970152660607303989700309153489211414)
                x := sub(sub(mm, low), lt(mm, low))
                seed := add(seed, 195312500000000000000000000000000000000000000000)
            }
            if iszero(lt(x, 1002251148292912915465673638866571192454241130208227099208420545124889760121)) {
                let mm :=
                    mulmod(x, 115532009551238127069034569024473762622767147147788687595329406319473705950071, not(0))
                let low := mul(x, 115532009551238127069034569024473762622767147147788687595329406319473705950071)
                x := sub(sub(mm, low), lt(mm, low))
                seed := add(seed, 97656250000000000000000000000000000000000000000)
            }
            if iszero(lt(x, 1001124941399879875885426434365711773271338418873287617190761945242904872061)) {
                let mm :=
                    mulmod(x, 115661976291793632079080739461244514212109858454009171777232224145244584379146, not(0))
                let low := mul(x, 115661976291793632079080739461244514212109858454009171777232224145244584379146)
                x := sub(sub(mm, low), lt(mm, low))
                seed := add(seed, 48828125000000000000000000000000000000000000000)
            }
            if iszero(lt(x, 1000562312602208636618511367809636978696490479831100413718397439177031575557)) {
                let mm :=
                    mulmod(x, 115727014478658864191206019837644585076293120248274136969870782148370783742109, not(0))
                let low := mul(x, 115727014478658864191206019837644585076293120248274136969870782148370783742109)
                x := sub(sub(mm, low), lt(mm, low))
                seed := add(seed, 24414062500000000000000000000000000000000000000)
            }
            if iszero(lt(x, 1000281116787780132399257365769687045617010004075711462195816279315578112995)) {
                let mm :=
                    mulmod(x, 115759547285228489644640649073775386641395351335601881572150779206589155570705, not(0))
                let low := mul(x, 115759547285228489644640649073775386641395351335601881572150779206589155570705)
                x := sub(sub(mm, low), lt(mm, low))
                seed := add(seed, 12207031250000000000000000000000000000000000000)
            }
            if iszero(lt(x, 1000140548516947258162771187858928924807657707067732580839449098218983450057)) {
                let mm :=
                    mulmod(x, 115775817117921914513665754670628277870063336875992169054789846993299520681056, not(0))
                let low := mul(x, 115775817117921914513665754670628277870063336875992169054789846993299520681056)
                x := sub(sub(mm, low), lt(mm, low))
                seed := add(seed, 6103515625000000000000000000000000000000000000)
            }
            if iszero(lt(x, 1000070271789411435538813638676535763208836739091941327682886747964405335251)) {
                let mm :=
                    mulmod(x, 115783952891761361996258436523111610648709418794355347035638479532448488583968, not(0))
                let low := mul(x, 115783952891761361996258436523111610648709418794355347035638479532448488583968)
                x := sub(sub(mm, low), lt(mm, low))
                seed := add(seed, 3051757812500000000000000000000000000000000000)
            }
            if iszero(lt(x, 1000035135277461856608582335861556633189962147970549360011398536055919590052)) {
                let mm :=
                    mulmod(x, 115788020993071844566540918178001145605824617021039977012160767671253988218160, not(0))
                let low := mul(x, 115788020993071844566540918178001145605824617021039977012160767671253988218160)
                x := sub(sub(mm, low), lt(mm, low))
                seed := add(seed, 1525878906250000000000000000000000000000000000)
            }
        }
        return (x, seed);
    }

    // slither-disable-end too-many-digits

    /// 10^x for a float x, rounded to nearest at 41 significant digits, half
    /// up. 10^k is exactly 10^k for an integer k.
    ///
    /// The fraction m of x, truncated to 1e-50, goes through `exp10Fixed`.
    /// Truncation moves 10^m by under 2.3026e-50 relative either way, and with
    /// exp10Fixed's bounds the true 10^x 1e50 is within 24 units below and
    /// `POW10_RAW_ERROR` units, 304.71 plus 23.03 rounded up, above the fixed
    /// point power, for a power below 1e51 units. A unit of the result is
    /// `POW_GUARD` of those, so the result is within half a unit plus 3.28e-8
    /// of a unit, and under 5.0000004e-41 relative.
    ///
    /// A nonzero fraction that truncates to zero is under 1e-50 from an
    /// integer, which puts 10^x within 2.4e-50 relative of the power of ten
    /// that is returned, far inside half a unit.
    ///
    /// @param signedCoefficient The signed coefficient of the floating point
    /// number.
    /// @param exponent The exponent of the floating point number.
    /// @return signedCoefficient The signed coefficient of the result.
    /// @return exponent The exponent of the result.
    function pow10(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        (signedCoefficient, exponent) = pow10Unrounded(signedCoefficient, exponent);
        if (signedCoefficient == 1) {
            return (1, exponent);
        }
        // POW_GUARD is 1e10 and so fits.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 guard = int256(POW_GUARD);
        return ((signedCoefficient + guard / 2) / guard, exponent + 10);
    }

    /// 10^x for a float x, with the guard digits that `pow10` rounds away: an
    /// exact 10^k as (1, k), otherwise the fixed point power of x's fraction
    /// at exponent characteristic - 50.
    ///
    /// @param signedCoefficient The signed coefficient of the floating point
    /// number.
    /// @param exponent The exponent of the floating point number.
    /// @return signedCoefficient The signed coefficient of the result.
    /// @return exponent The exponent of the result.
    function pow10Unrounded(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        (int256 integer, int256 frac) = intFrac(signedCoefficient, exponent);
        int256 characteristic = withTargetExponent(integer, exponent, 0);
        int256 mantissa = frac == 0 ? int256(0) : withTargetExponent(frac, exponent, -50);
        if (mantissa < 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            mantissa += int256(POW_FIXED_ONE);
            characteristic -= 1;
        }
        if (mantissa == 0) {
            return (1, characteristic);
        }
        // mantissa is in (0, 1e50) and so is not negative, and the power is
        // below 1e51 and so fits.
        // forge-lint: disable-next-line(unsafe-typecast)
        return (int256(exp10Fixed(uint256(mantissa))), characteristic - 50);
    }

    /// 10^x at the `POW_FIXED_ONE` scale. Each binary digit 2^-i of x, for i
    /// in [1, 16], multiplies in 10^(2^-i), and the r below 2^-16 that is left
    /// goes through the Taylor series of 10^r to its ninth power by Horner's
    /// rule. Every constant and every product is floored, so the result is
    /// never above 10^x.
    ///
    /// The result is within [-3.048e-49, 0] relative of 10^x. In units of
    /// 1e-50 relative:
    /// - Each 10^(2^-i) constant is under a unit below 10^(2^-i) 1e50, and
    ///   each multiply after the first floors under a unit of a product of at
    ///   least 10^(2^-i) 1e50, so the digits lose under the sum of
    ///   2 / 10^(2^-i) less the first multiply's, 28.392.
    /// - The floored coefficients and steps leave the series under
    ///   1 + 2r / (1 - r) below its nine terms, and the terms past the ninth
    ///   sum under 0.079, so it is under 1.079 below 10^r, which is at least 1.
    /// - The last multiply floors under a unit.
    /// In all that is under 30.471.
    /// @param x The exponent at the `POW_FIXED_ONE` scale, in [0, 1).
    /// @return result The power at the `POW_FIXED_ONE` scale, in [1, 10).
    //slither-disable-next-line cyclomatic-complexity
    function exp10Fixed(uint256 x) internal pure returns (uint256 result) {
        unchecked {
            result = POW_FIXED_ONE;
            if (x >= 5e49) {
                x -= 5e49;
                result = 316227766016837933199889354443271853371955513932521;
            }
            if (x >= 2.5e49) {
                x -= 2.5e49;
                result = mulDivFixed(result, 177827941003892280122542119519268484473579052640225);
            }
            if (x >= 1.25e49) {
                x -= 1.25e49;
                result = mulDivFixed(result, 133352143216332402567593171529533109241566796476437);
            }
            if (x >= 6.25e48) {
                x -= 6.25e48;
                result = mulDivFixed(result, 115478198468945817966648288729550828156694804147961);
            }
            if (x >= 3.125e48) {
                x -= 3.125e48;
                result = mulDivFixed(result, 107460782832131749721594153196434359466719822837527);
            }
            if (x >= 1.5625e48) {
                x -= 1.5625e48;
                result = mulDivFixed(result, 103663292843769799729165172492534446770887303110100);
            }
            if (x >= 7.8125e47) {
                x -= 7.8125e47;
                result = mulDivFixed(result, 101815172171818184147422688857883534761587963866759);
            }
            if (x >= 3.90625e47) {
                x -= 3.90625e47;
                result = mulDivFixed(result, 100903504484144743775925442390642133138116897958823);
            }
            if (x >= 1.953125e47) {
                x -= 1.953125e47;
                result = mulDivFixed(result, 100450736425446251566479469434131766413696548644885);
            }
            if (x >= 9.765625e46) {
                x -= 9.765625e46;
                result = mulDivFixed(result, 100225114829291291546567363886657119245424113020822);
            }
            if (x >= 4.8828125e46) {
                x -= 4.8828125e46;
                result = mulDivFixed(result, 100112494139987987588542643436571177327133841887328);
            }
            if (x >= 2.44140625e46) {
                x -= 2.44140625e46;
                result = mulDivFixed(result, 100056231260220863661851136780963697869649047983110);
            }
            if (x >= 1.220703125e46) {
                x -= 1.220703125e46;
                result = mulDivFixed(result, 100028111678778013239925736576968704561701000407571);
            }
            if (x >= 6.103515625e45) {
                x -= 6.103515625e45;
                result = mulDivFixed(result, 100014054851694725816277118785892892480765770706773);
            }
            if (x >= 3.0517578125e45) {
                x -= 3.0517578125e45;
                result = mulDivFixed(result, 100007027178941143553881363867653576320883673909194);
            }
            if (x >= 1.52587890625e45) {
                x -= 1.52587890625e45;
                result = mulDivFixed(result, 100003513527746185660858233586155663318996214797054);
            }
            uint256 series = 501392883377544009807090987164215453583108663277;
            series = 1959769462647852369682789087147690310674843760584 + mulDivFixed(series, x);
            series = 6808936507443706236540404026537606122629959236393 + mulDivFixed(series, x);
            series = 20699584869686809669966601589738494188245922773010 + mulDivFixed(series, x);
            series = 53938292919558141019969155571017253478007614081814 + mulDivFixed(series, x);
            series = 117125514891226696317825761603265234076100689858139 + mulDivFixed(series, x);
            series = 203467859229347619683099119171381053024105502647771 + mulDivFixed(series, x);
            series = 265094905523919900528083319429700884579872503956640 + mulDivFixed(series, x);
            series = POW_FIXED_LN10 + mulDivFixed(series, x);
            series = POW_FIXED_ONE + mulDivFixed(series, x);
            result = mulDivFixed(result, series);
        }
    }

    /// Maximizes a float's signed coefficient by increasing its magnitude
    /// and decreasing its exponent accordingly. Greatly simplified a lot of
    /// internal logic that involves comparing signed coefficients as integers,
    /// or wanting them to have comparable magnitudes.
    ///
    /// The coefficient is always fully maximized. Near `type(int256).min` the
    /// exponent cannot take the whole shift, so it stops at the floor and the
    /// digits it could not take are returned as the shortfall. The input value
    /// is then `signedCoefficient * 10^(exponent - shortfall)`.
    /// @return signedCoefficient The maximized signed coefficient.
    /// @return exponent The maximized exponent.
    /// @return shortfall The digits of shift the exponent could not take, in
    /// [0, 76]. Nonzero only when the exponent is `type(int256).min`.
    function maximize(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256, int256) {
        unchecked {
            if (signedCoefficient == 0) {
                return (MAXIMIZED_ZERO_SIGNED_COEFFICIENT, MAXIMIZED_ZERO_EXPONENT, 0);
            }

            int256 maximizedExponent = exponent;
            // Check if already maximized before dropping into a block full of
            // jumps.
            if (signedCoefficient / 1e75 == 0) {
                if (signedCoefficient / 1e38 == 0) {
                    signedCoefficient *= 1e38;
                    maximizedExponent -= 38;
                }

                if (signedCoefficient / 1e57 == 0) {
                    signedCoefficient *= 1e19;
                    maximizedExponent -= 19;
                }

                if (signedCoefficient / 1e66 == 0) {
                    signedCoefficient *= 1e10;
                    maximizedExponent -= 10;
                }

                while (signedCoefficient / 1e74 == 0) {
                    signedCoefficient *= 1e2;
                    maximizedExponent -= 2;
                }

                if (signedCoefficient / 1e75 == 0) {
                    signedCoefficient *= 10;
                    maximizedExponent -= 1;
                }
            }

            // Maybe we can fit in one more OOM without overflow, but we won't
            // know until we try. This pushes us into [1e76,type(int256).max] and
            // [-type(int256).max,-1e76] ranges, if that's possible.
            int256 trySignedCoefficient = signedCoefficient * 10;
            if (signedCoefficient == trySignedCoefficient / 10) {
                signedCoefficient = trySignedCoefficient;
                maximizedExponent -= 1;
            }

            // The shift is at most 76, so the exponent wrapped past the floor
            // exactly when it went up.
            if (maximizedExponent > exponent) {
                return (signedCoefficient, type(int256).min, type(int256).max - maximizedExponent + 1);
            }
            return (signedCoefficient, maximizedExponent, 0);
        }
    }

    /// Maximizes a float as per `maximize` but errors if the exponent cannot
    /// take the whole shift. This is analogous to other functions in the lib
    /// that are "lossless".
    /// @param signedCoefficient The signed coefficient.
    /// @param exponent The exponent.
    /// @return signedCoefficient The maximized signed coefficient.
    /// @return exponent The maximized exponent.
    function maximizeFull(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        (int256 trySignedCoefficient, int256 tryExponent, int256 shortfall) = maximize(signedCoefficient, exponent);
        if (shortfall != 0) {
            revert MaximizeOverflow(signedCoefficient, exponent);
        }
        return (trySignedCoefficient, tryExponent);
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
    /// @param signedCoefficientA The signed coefficient of the first float.
    /// @param exponentA The exponent of the first float.
    /// @param signedCoefficientB The signed coefficient of the second float.
    /// @param exponentB The exponent of the second float.
    /// @return rescaledA The rescaled coefficient of the first float.
    /// @return rescaledB The rescaled coefficient of the second float.
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
                    noopRescale := or(
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
            // exponentDiff [0, 76]
            // forge-lint: disable-next-line(unsafe-typecast)
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

    /// The magnitude of an unpacked coefficient. The exponent is untouched by
    /// taking a magnitude, so there is nothing to return alongside it.
    ///
    /// The packed `LibDecimalFloat.abs` cannot serve callers working below the
    /// public arithmetic surface. It has to fit the magnitude back into an
    /// int224, so for the most negative coefficient it raises the exponent,
    /// and reverts `ExponentOverflow` when the exponent is already at its
    /// maximum. Here the coefficient is already widened to an int256, so
    /// negating an int224 is exact and cannot overflow.
    /// @param signedCoefficient The coefficient, within int224.
    /// @return The non-negative coefficient.
    function absCoefficient(int256 signedCoefficient) internal pure returns (int256) {
        return signedCoefficient < 0 ? -signedCoefficient : signedCoefficient;
    }

    /// Whether A is less than B, without packing either.
    /// @param signedCoefficientA The first coefficient.
    /// @param exponentA The first exponent.
    /// @param signedCoefficientB The second coefficient.
    /// @param exponentB The second exponent.
    /// @return Whether A < B.
    function lt(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (bool)
    {
        (int256 rescaledA, int256 rescaledB) =
            compareRescale(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        return rescaledA < rescaledB;
    }

    /// Whether A is less than or equal to B, without packing either.
    /// @param signedCoefficientA The first coefficient.
    /// @param exponentA The first exponent.
    /// @param signedCoefficientB The second coefficient.
    /// @param exponentB The second exponent.
    /// @return Whether A <= B.
    function lte(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (bool)
    {
        (int256 rescaledA, int256 rescaledB) =
            compareRescale(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        return rescaledA <= rescaledB;
    }

    /// Whether A is greater than B, without packing either.
    /// @param signedCoefficientA The first coefficient.
    /// @param exponentA The first exponent.
    /// @param signedCoefficientB The second coefficient.
    /// @param exponentB The second exponent.
    /// @return Whether A > B.
    function gt(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (bool)
    {
        (int256 rescaledA, int256 rescaledB) =
            compareRescale(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        return rescaledA > rescaledB;
    }

    /// Whether A is greater than or equal to B, without packing either.
    /// @param signedCoefficientA The first coefficient.
    /// @param exponentA The first exponent.
    /// @param signedCoefficientB The second coefficient.
    /// @param exponentB The second exponent.
    /// @return Whether A >= B.
    function gte(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (bool)
    {
        (int256 rescaledA, int256 rescaledB) =
            compareRescale(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        return rescaledA >= rescaledB;
    }

    /// The smaller of two unpacked values, without packing either.
    ///
    /// Ties return B, so that `min(x, x)` is stable whichever representation
    /// of a numerically equal pair is passed second.
    /// @param signedCoefficientA The first coefficient.
    /// @param exponentA The first exponent.
    /// @param signedCoefficientB The second coefficient.
    /// @param exponentB The second exponent.
    /// @return The smaller value's coefficient.
    /// @return The smaller value's exponent.
    function min(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
        return gte(signedCoefficientA, exponentA, signedCoefficientB, exponentB)
            ? (signedCoefficientB, exponentB)
            : (signedCoefficientA, exponentA);
    }

    /// The larger of two unpacked values, without packing either.
    ///
    /// Ties return B, so that `max(x, x)` is stable whichever representation
    /// of a numerically equal pair is passed second.
    /// @param signedCoefficientA The first coefficient.
    /// @param exponentA The first exponent.
    /// @param signedCoefficientB The second coefficient.
    /// @param exponentB The second exponent.
    /// @return The larger value's coefficient.
    /// @return The larger value's exponent.
    function max(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
        return lte(signedCoefficientA, exponentA, signedCoefficientB, exponentB)
            ? (signedCoefficientB, exponentB)
            : (signedCoefficientA, exponentA);
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
                if (exponentDiff > 76 || exponentDiff <= 0) {
                    return (MAXIMIZED_ZERO_SIGNED_COEFFICIENT);
                }
                // exponentDiff [1, 76]
                // forge-lint: disable-next-line(unsafe-typecast)
                return signedCoefficient / int256(10 ** uint256(exponentDiff));
            } else {
                int256 exponentDiff = exponent - targetExponent;
                if (exponentDiff > 76 || exponentDiff <= 0) {
                    revert WithTargetExponentOverflow(signedCoefficient, exponent, targetExponent);
                }
                // exponentDiff [1, 76]
                // forge-lint: disable-next-line(unsafe-typecast)
                int256 scale = int256(10 ** uint256(exponentDiff));
                int256 rescaled = signedCoefficient * scale;
                if (rescaled / scale != signedCoefficient) {
                    revert WithTargetExponentOverflow(signedCoefficient, exponent, targetExponent);
                }
                return rescaled;
            }
        }
    }

    /// Returns the integer and fractional parts of a float. Both parts retain
    /// the sign and exponent of the input float such that integer + frac =
    /// original float. For all non negative exponents, frac is 0 and the integer
    /// part is the original float. For exponents less than -76, the corollary is
    /// true: integer is always 0 and frac is the original float.
    /// @param signedCoefficient The signed coefficient.
    /// @param exponent The exponent.
    /// @return integer The integer part of the float.
    /// @return frac The fractional part of the float.
    function intFrac(int256 signedCoefficient, int256 exponent) internal pure returns (int256 integer, int256 frac) {
        unchecked {
            // if exponent is not negative the integer part is the number
            // itself and the fractional part is 0.
            if (exponent >= 0) {
                return (signedCoefficient, 0);
            }

            // If the exponent is less than -76, the integer part is 0.
            // and the fractional part is the whole coefficient.
            if (exponent < -76) {
                return (0, signedCoefficient);
            }

            // exponent [-76, -1]
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 unit = int256(10 ** uint256(-exponent));
            frac = signedCoefficient % unit;
            integer = signedCoefficient - frac;
        }
    }
}
