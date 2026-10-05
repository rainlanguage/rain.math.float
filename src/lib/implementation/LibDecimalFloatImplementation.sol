// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    ExponentOverflow,
    Log10Negative,
    Log10Zero,
    MulDivOverflow,
    DivisionByZero,
    MaximizeOverflow
} from "../../error/ErrDecimalFloat.sol";
import {LOG_TABLE_SIZE_BYTES, LOG_TABLE_SIZE_BASE} from "../table/LibLogTable.sol";

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

/// @dev ln(10) at the `POW_FIXED_ONE` scale, rounded to nearest.
uint256 constant POW_FIXED_LN10 = 230258509299404568401799145468436420760110148862877;

/// @dev 2 / ln(10) at the `POW_FIXED_ONE` scale, rounded to nearest.
uint256 constant POW_FIXED_TWO_OVER_LN10 = 86858896380650365530225783783321016458879401160733;

/// @dev 2^-16 at the `POW_FIXED_ONE` scale, the last binary digit
/// `exp10Fixed` reduces by.
uint256 constant POW_FIXED_BINARY_STEP = 1525878906250000000000000000000000000000000000;

/// @dev The inverse of 5^50 modulo 2^256, which divides a multiple of
/// `POW_FIXED_ONE` by it once the factor 2^50 is shifted out.
uint256 constant POW_FIXED_ONE_ODD_INVERSE =
    32019276099673541610834237427944372346803171054071557274126404137164986125033;

/// @dev Guard digits pow10 rounds away, so that its error stays below half a
/// unit of the result and an exact power comes out exact.
uint256 constant POW_GUARD = 1e10;

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

            // adjustExponent [0, 76]
            // forge-lint: disable-next-line(unsafe-typecast)
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
            bool fullA;
            bool fullB;
            // Move both coefficients into the e75/e76 range, so that the result
            // of division will not cause a mulDiv overflow.
            (signedCoefficientA, exponentA, fullA) = maximize(signedCoefficientA, exponentA);
            (signedCoefficientB, exponentB, fullB) = maximize(signedCoefficientB, exponentB);

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
                if (fullB) {
                    scale = 1e75;
                    adjustExponent = 75;
                } else {
                    if (signedCoefficientBAbs < 1e38) {
                        if (signedCoefficientBAbs < 1e19) {
                            if (signedCoefficientBAbs < 1e10) {
                                if (signedCoefficientBAbs < 1e5) {
                                    scale = 1e5;
                                    adjustExponent = 5;
                                } else {
                                    scale = 1e10;
                                    adjustExponent = 10;
                                }
                            } else {
                                if (signedCoefficientBAbs < 1e14) {
                                    scale = 1e14;
                                    adjustExponent = 14;
                                } else {
                                    scale = 1e19;
                                    adjustExponent = 19;
                                }
                            }
                        } else {
                            if (signedCoefficientBAbs < 1e28) {
                                if (signedCoefficientBAbs < 1e23) {
                                    scale = 1e23;
                                    adjustExponent = 23;
                                } else {
                                    scale = 1e28;
                                    adjustExponent = 28;
                                }
                            } else {
                                if (signedCoefficientBAbs < 1e33) {
                                    scale = 1e33;
                                    adjustExponent = 33;
                                } else {
                                    scale = 1e38;
                                    adjustExponent = 38;
                                }
                            }
                        }
                    } else {
                        if (signedCoefficientBAbs < 1e58) {
                            if (signedCoefficientBAbs < 1e48) {
                                if (signedCoefficientBAbs < 1e43) {
                                    scale = 1e43;
                                    adjustExponent = 43;
                                } else {
                                    scale = 1e48;
                                    adjustExponent = 48;
                                }
                            } else {
                                if (signedCoefficientBAbs < 1e53) {
                                    scale = 1e53;
                                    adjustExponent = 53;
                                } else {
                                    scale = 1e58;
                                    adjustExponent = 58;
                                }
                            }
                        } else {
                            if (signedCoefficientBAbs < 1e68) {
                                if (signedCoefficientBAbs < 1e63) {
                                    scale = 1e63;
                                    adjustExponent = 63;
                                } else {
                                    scale = 1e68;
                                    adjustExponent = 68;
                                }
                            } else {
                                if (signedCoefficientBAbs < 1e73) {
                                    scale = 1e73;
                                    adjustExponent = 73;
                                } else {
                                    // Noop as we already have a starting scale.
                                }
                            }
                        }
                    }

                    // Finalize the scale after the binary search.
                    while (signedCoefficientBAbs <= scale) {
                        unchecked {
                            scale /= 10;
                            adjustExponent -= 1;
                        }
                    }
                    if (scale == 0) {
                        revert MaximizeOverflow(signedCoefficientB, exponentB);
                    }
                }
                if (!fullA) {
                    revert MaximizeOverflow(signedCoefficientA, exponentA);
                }
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

                exponent = exponentA + underflowExponentBy - exponentB;

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
            let remainder := mulmod(x, y, 100000000000000000000000000000000000000000000000000)
            let prod1 := sub(sub(sub(mm, prod0), lt(mm, prod0)), gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
            result := mul(or(shr(50, prod0), shl(206, prod1)), inverse)
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
        (signedCoefficientA, exponentA) = maximizeFull(signedCoefficientA, exponentA);
        (signedCoefficientB, exponentB) = maximizeFull(signedCoefficientB, exponentB);

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
            // exponentA >= exponentB so exponentA - exponentB will fit in
            // uint256.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 alignmentExponentDiff = uint256(exponentA - exponentB);
            // The early return here allows us to do unchecked pow on the
            // scaler and means we never revert due to overflow here.
            if (alignmentExponentDiff > ADD_MAX_EXPONENT_DIFF) {
                return (signedCoefficientA, exponentA);
            }
            // alignmentExponentDiff can't be greater than 76 so will pow
            // without truncation.
            // forge-lint: disable-next-line(unsafe-typecast)
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

    /// Looks up the log10 table value for a given index.
    /// @param tables The address of the log tables data contract.
    /// @param index The index into the log table.
    /// @return result The log10 table value.
    function lookupLogTableVal(address tables, uint256 index) internal view returns (uint256 result) {
        // Skip first byte of data contract.
        uint256 smallTableOffset = LOG_TABLE_SIZE_BYTES + 1;
        uint256 logTableSizeBase = LOG_TABLE_SIZE_BASE;
        assembly ("memory-safe") {
            // First byte of the data contract must be skipped.
            // truncation from the div by 10 is intentional here to keep the
            // main offset and small offset distinct.
            // slither-disable-next-line divide-before-multiply
            let mainOffset := add(1, mul(div(index, 10), 2))
            mstore(0, 0)
            extcodecopy(tables, 30, mainOffset, 2)
            let mainTableVal := mload(0)

            result := and(mainTableVal, 0x7FFF)
            if iszero(iszero(and(mainTableVal, 0x8000))) {
                smallTableOffset := add(smallTableOffset, logTableSizeBase)
            }

            mstore(0, 0)
            // truncation from the div by 100 is intentional here to keep the
            // small table offset and small offset distinct.
            // slither-disable-next-line divide-before-multiply
            extcodecopy(tables, 31, add(smallTableOffset, add(mul(div(index, 100), 10), mod(index, 10))), 1)
            result := add(result, mload(0))
        }
    }

    /// log10(x) for a float x.
    ///
    /// The four figure log table gives a seed and the atanh series of the
    /// ratio between the input and 10^seed closes the remaining gap. The
    /// absolute error is below 1e-46. Inputs within a table step of a power of
    /// ten take an exact seed, so a log near zero keeps its relative precision.
    ///
    /// @param tablesDataContract The address of the log tables data contract.
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
        {
            int256 unmaximizedCoefficient = signedCoefficient;
            int256 unmaximizedExponent = exponent;
            (signedCoefficient, exponent) = maximizeFull(signedCoefficient, exponent);

            if (signedCoefficient <= 0) {
                if (signedCoefficient == 0) {
                    revert Log10Zero();
                } else {
                    revert Log10Negative(unmaximizedCoefficient, unmaximizedExponent);
                }
            }
        }

        if (signedCoefficient >= 1e76) {
            signedCoefficient /= 10;
            exponent += 1;
        }
        if (signedCoefficient == 1e75) {
            return (exponent + 75, 0);
        }

        // log10(estimate / 1e75) = seed / 1e50
        int256 seed;
        uint256 estimate;
        if (signedCoefficient < 1.001e75) {
            estimate = 1e75;
        } else if (signedCoefficient >= 9.999e75) {
            seed = 1e50;
            estimate = 1e76;
        } else {
            unchecked {
                // signedCoefficient is in [1.001e75, 9.999e75) so idx is in
                // [1, 8998].
                // forge-lint: disable-next-line(unsafe-typecast)
                uint256 idx = uint256(signedCoefficient / 1e72 - 1000);
                uint256 tableSeed = lookupLogTableVal(tablesDataContract, idx) * 1e46;
                // A whole number of 2^-16 steps, which exp10Fixed raises with
                // its digit constants alone.
                // forge-lint: disable-next-line(unsafe-typecast)
                seed = int256(tableSeed - tableSeed % POW_FIXED_BINARY_STEP);
            }
            // seed is in (0, 1e50) and so is not negative.
            // forge-lint: disable-next-line(unsafe-typecast)
            estimate = exp10Fixed(uint256(seed)) * 1e25;
        }

        // signedCoefficient is positive.
        // forge-lint: disable-next-line(unsafe-typecast)
        (int256 correctionCoefficient, int256 correctionExponent) = log10Ratio(uint256(signedCoefficient), estimate);
        exponent += 75;
        if ((exponent == 0 && seed == 0) || (exponent == -1 && seed == 1e50)) {
            return (correctionCoefficient, correctionExponent);
        }
        // Otherwise the log is at least 2^-16, so 66 places keep more than the
        // 48 digits the correction carries.
        if (exponent > -1e10 && exponent < 1e10) {
            int256 correction = withTargetExponent(correctionCoefficient, correctionExponent, -66);
            return (exponent * 1e66 + seed * 1e16 + correction, -66);
        }
        (int256 integerCoefficient, int256 integerExponent) = add(exponent, 0, seed, -50);
        return add(integerCoefficient, integerExponent, correctionCoefficient, correctionExponent);
    }

    /// log10(a / b) as a float, by 2 atanh((a - b) / (a + b)) / ln(10), for
    /// a and b within a few parts in ten thousand of each other.
    /// @param a The numerator, at most 1e76.
    /// @param b The denominator, at most 1e76.
    /// @return signedCoefficient The signed coefficient of the log.
    /// @return exponent The exponent of the log.
    function log10Ratio(uint256 a, uint256 b) internal pure returns (int256, int256) {
        bool below = a < b;
        uint256 difference = below ? b - a : a - b;
        if (difference == 0) {
            return (0, 0);
        }
        uint256 sum = a + b;
        uint256 z = mulDiv(difference, POW_FIXED_ONE, sum);
        uint256 zSquared = mulDivFixed(z, z);
        // atanh(z) / z
        uint256 series = POW_FIXED_ONE;
        uint256 term = POW_FIXED_ONE;
        for (uint256 k = 3; term > 0; k += 2) {
            term = mulDivFixed(term, zSquared);
            series += term / k;
        }
        // Scale the difference into [1e74, 1e76].
        int256 differenceExponent = -52;
        unchecked {
            if (difference < 1e37) {
                difference *= 1e37;
                differenceExponent -= 37;
            }
            if (difference < 1e56) {
                difference *= 1e19;
                differenceExponent -= 19;
            }
            if (difference < 1e65) {
                difference *= 1e10;
                differenceExponent -= 10;
            }
            if (difference < 1e70) {
                difference *= 1e5;
                differenceExponent -= 5;
            }
            if (difference < 1e72) {
                difference *= 1e3;
                differenceExponent -= 3;
            }
            if (difference < 1e74) {
                difference *= 1e2;
                differenceExponent -= 2;
            }
        }
        // The quotient is in (4e49, 5e52) and so fits.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedCoefficient = int256(mulDiv(difference, mulDivFixed(series, POW_FIXED_TWO_OVER_LN10) * 100, sum));
        return (below ? -signedCoefficient : signedCoefficient, differenceExponent);
    }

    /// 10^x for a float x.
    ///
    /// The fractional part of x goes through `exp10Fixed` and the result is
    /// rounded to 41 significant digits, so it is within half a unit in the
    /// 41st digit of the true value and an exactly representable power such
    /// as 10^2 is exact.
    ///
    /// @param signedCoefficient The signed coefficient of the floating point
    /// number.
    /// @param exponent The exponent of the floating point number.
    /// @return signedCoefficient The signed coefficient of the result.
    /// @return exponent The exponent of the result.
    function pow10(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
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
        // mantissa is in (0, 1e50) and so is not negative, and the rounded
        // power is at most 1e41 and so fits.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 power = int256((exp10Fixed(uint256(mantissa)) + POW_GUARD / 2) / POW_GUARD);
        return (power, characteristic - 40);
    }

    /// 10^x at the `POW_FIXED_ONE` scale. Each of the first 16 binary digits of
    /// x multiplies in 10^(2^-i), rounded to nearest. The remainder, below
    /// 2^-16, goes through the degree 9 Taylor polynomial of e^(r ln 10), whose
    /// truncation error is below 1e-51 relative.
    /// @param x The exponent at the `POW_FIXED_ONE` scale, in [0, 1].
    /// @return The power at the `POW_FIXED_ONE` scale, in [1, 10].
    function exp10Fixed(uint256 x) internal pure returns (uint256) {
        unchecked {
            uint256 result = POW_FIXED_ONE;
            if (x >= 50000000000000000000000000000000000000000000000000) {
                x -= 50000000000000000000000000000000000000000000000000;
                result = 316227766016837933199889354443271853371955513932522;
            }
            if (x >= 25000000000000000000000000000000000000000000000000) {
                x -= 25000000000000000000000000000000000000000000000000;
                result = mulDivFixed(result, 177827941003892280122542119519268484473579052640226);
            }
            if (x >= 12500000000000000000000000000000000000000000000000) {
                x -= 12500000000000000000000000000000000000000000000000;
                result = mulDivFixed(result, 133352143216332402567593171529533109241566796476437);
            }
            if (x >= 6250000000000000000000000000000000000000000000000) {
                x -= 6250000000000000000000000000000000000000000000000;
                result = mulDivFixed(result, 115478198468945817966648288729550828156694804147961);
            }
            if (x >= 3125000000000000000000000000000000000000000000000) {
                x -= 3125000000000000000000000000000000000000000000000;
                result = mulDivFixed(result, 107460782832131749721594153196434359466719822837528);
            }
            if (x >= 1562500000000000000000000000000000000000000000000) {
                x -= 1562500000000000000000000000000000000000000000000;
                result = mulDivFixed(result, 103663292843769799729165172492534446770887303110100);
            }
            if (x >= 781250000000000000000000000000000000000000000000) {
                x -= 781250000000000000000000000000000000000000000000;
                result = mulDivFixed(result, 101815172171818184147422688857883534761587963866760);
            }
            if (x >= 390625000000000000000000000000000000000000000000) {
                x -= 390625000000000000000000000000000000000000000000;
                result = mulDivFixed(result, 100903504484144743775925442390642133138116897958824);
            }
            if (x >= 195312500000000000000000000000000000000000000000) {
                x -= 195312500000000000000000000000000000000000000000;
                result = mulDivFixed(result, 100450736425446251566479469434131766413696548644886);
            }
            if (x >= 97656250000000000000000000000000000000000000000) {
                x -= 97656250000000000000000000000000000000000000000;
                result = mulDivFixed(result, 100225114829291291546567363886657119245424113020823);
            }
            if (x >= 48828125000000000000000000000000000000000000000) {
                x -= 48828125000000000000000000000000000000000000000;
                result = mulDivFixed(result, 100112494139987987588542643436571177327133841887329);
            }
            if (x >= 24414062500000000000000000000000000000000000000) {
                x -= 24414062500000000000000000000000000000000000000;
                result = mulDivFixed(result, 100056231260220863661851136780963697869649047983110);
            }
            if (x >= 12207031250000000000000000000000000000000000000) {
                x -= 12207031250000000000000000000000000000000000000;
                result = mulDivFixed(result, 100028111678778013239925736576968704561701000407571);
            }
            if (x >= 6103515625000000000000000000000000000000000000) {
                x -= 6103515625000000000000000000000000000000000000;
                result = mulDivFixed(result, 100014054851694725816277118785892892480765770706773);
            }
            if (x >= 3051757812500000000000000000000000000000000000) {
                x -= 3051757812500000000000000000000000000000000000;
                result = mulDivFixed(result, 100007027178941143553881363867653576320883673909194);
            }
            if (x >= 1525878906250000000000000000000000000000000000) {
                x -= 1525878906250000000000000000000000000000000000;
                result = mulDivFixed(result, 100003513527746185660858233586155663318996214797055);
            }
            if (x == 0) {
                return result;
            }
            uint256 polynomial = 501392883377544009807090987164215453583108663278;
            polynomial = 1959769462647852369682789087147690310674843760585 + mulDivFixed(polynomial, x);
            polynomial = 6808936507443706236540404026537606122629959236393 + mulDivFixed(polynomial, x);
            polynomial = 20699584869686809669966601589738494188245922773011 + mulDivFixed(polynomial, x);
            polynomial = 53938292919558141019969155571017253478007614081814 + mulDivFixed(polynomial, x);
            polynomial = 117125514891226696317825761603265234076100689858139 + mulDivFixed(polynomial, x);
            polynomial = 203467859229347619683099119171381053024105502647772 + mulDivFixed(polynomial, x);
            polynomial = 265094905523919900528083319429700884579872503956640 + mulDivFixed(polynomial, x);
            polynomial = 230258509299404568401799145468436420760110148862877 + mulDivFixed(polynomial, x);
            polynomial = 100000000000000000000000000000000000000000000000000 + mulDivFixed(polynomial, x);
            return mulDivFixed(result, polynomial);
        }
    }

    /// Maximizes a float's signed coefficient by increasing its magnitude
    /// and decreasing its exponent accordingly. Greatly simplified a lot of
    /// internal logic that involves comparing signed coefficients as integers,
    /// or wanting them to have comparable magnitudes.
    /// @return signedCoefficient The maximized signed coefficient.
    /// @return exponent The maximized exponent.
    /// @return full `true` if the result is fully maximized, `false` if it was
    /// not possible to maximize without overflow.
    function maximize(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256, bool) {
        unchecked {
            if (signedCoefficient == 0) {
                // The literal is the bool this function returns, not a condition operand.
                //forge-lint: disable-next-line(boolean-cst)
                return (MAXIMIZED_ZERO_SIGNED_COEFFICIENT, MAXIMIZED_ZERO_EXPONENT, true);
            }

            // Check if already maximized before dropping into a block full of
            // jumps.
            if (signedCoefficient / 1e75 == 0) {
                if (signedCoefficient / 1e38 == 0 && exponent >= type(int256).min + 38) {
                    signedCoefficient *= 1e38;
                    exponent -= 38;
                }

                if (signedCoefficient / 1e57 == 0 && exponent >= type(int256).min + 19) {
                    signedCoefficient *= 1e19;
                    exponent -= 19;
                }

                if (signedCoefficient / 1e66 == 0 && exponent >= type(int256).min + 10) {
                    signedCoefficient *= 1e10;
                    exponent -= 10;
                }

                while (signedCoefficient / 1e74 == 0 && exponent >= type(int256).min + 2) {
                    signedCoefficient *= 1e2;
                    exponent -= 2;
                }

                if (signedCoefficient / 1e75 == 0 && exponent >= type(int256).min + 1) {
                    signedCoefficient *= 10;
                    exponent -= 1;
                }
            }

            // Maybe we can fit in one more OOM without overflow, but we won't
            // know until we try. This pushes us into [1e76,type(int256).max] and
            // [-type(int256).max,-1e76] ranges, if that's possible.
            int256 trySignedCoefficient = signedCoefficient * 10;
            if (signedCoefficient == trySignedCoefficient / 10 && exponent >= type(int256).min + 1) {
                signedCoefficient = trySignedCoefficient;
                exponent -= 1;
            }

            return (signedCoefficient, exponent, signedCoefficient / 1e75 != 0);
        }
    }

    /// Maximizes a float as per `maximize` but errors if not fully maximized.
    /// This is analogous to other functions in the lib that are "lossless".
    /// @param signedCoefficient The signed coefficient.
    /// @param exponent The exponent.
    /// @return signedCoefficient The maximized signed coefficient.
    /// @return exponent The maximized exponent.
    function maximizeFull(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        (int256 trySignedCoefficient, int256 tryExponent, bool full) = maximize(signedCoefficient, exponent);
        if (!full) {
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
