// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {ExponentOverflow, DivisionByZero, MaximizeOverflow, MulDivOverflow} from "../../src/error/ErrDecimalFloat.sol";
import {
    ADD_MAX_EXPONENT_DIFF,
    MAXIMIZED_ZERO_SIGNED_COEFFICIENT,
    MAXIMIZED_ZERO_EXPONENT
} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";

/// `maximize`, `maximizeFull`, `div`, `add`, `sub` and `inv` verbatim
/// from `src/lib/implementation/LibDecimalFloatImplementation.sol` at main
/// 2b19ed13b90420ffc74dcb528f9f67e9e71b315e, before `maximize` returned a
/// shortfall, with every helper they call copied from the same commit, so they
/// call nothing on the live library. EQUIVALENCE BASELINE ONLY, NEVER A VALUE
/// ORACLE: it copies the old steps, including the mixed-sign add rounding of
/// #340, so agreeing with it says nothing about a value. Expected values come
/// from `LibExactFloat` over exact math.
library LibDecimalFloatImplementationMain {
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

    function maximizeFull(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        (int256 trySignedCoefficient, int256 tryExponent, bool full) = maximize(signedCoefficient, exponent);
        if (!full) {
            revert MaximizeOverflow(signedCoefficient, exponent);
        }
        return (trySignedCoefficient, tryExponent);
    }

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
            int256 exponent = 0;
            bool fullA;
            bool fullB;
            // Move both coefficients into the e75/e76 range, so that the result
            // of division will not cause a mulDiv overflow.
            (signedCoefficientA, exponentA, fullA) = maximize(signedCoefficientA, exponentA);
            (signedCoefficientB, exponentB, fullB) = maximize(signedCoefficientB, exponentB);
            // exponentA is pinned at its minimum, so the digits it cannot take
            // join adjustExponent, which spills onto exponentB. `exponent` holds
            // that shift until the quotient exponent is computed.
            if (!fullA) {
                (signedCoefficientA, exponent) = maximizeFull(signedCoefficientA, 0);
            }

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
            }
            adjustExponent -= exponent;

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

    function sub(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
        (signedCoefficientB, exponentB) = minus(signedCoefficientB, exponentB);
        return add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    function inv(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        return div(1e76, -76, signedCoefficient, exponent);
    }

    // The helpers the copies above call, verbatim from the same commit, so
    // this baseline calls nothing on the live library.

    /// Returns the absolute value of a signed coefficient as an unsigned
    /// integer.
    /// @param signedCoefficient The signed coefficient.
    /// @return The absolute value as an unsigned integer.
    function absUnsignedSignedCoefficient(int256 signedCoefficient) private pure returns (uint256) {
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
        private
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

    /// mulDiv as seen in Open Zeppelin, PRB Math, Solady, and other libraries.
    /// Credit to Remco Bloemen under MIT license: https://2π.com/21/muldiv
    function mulDiv(uint256 x, uint256 y, uint256 denominator) private pure returns (uint256 result) {
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

    /// mul512 from Open Zeppelin.
    /// Simply part of the original mulDiv function abstracted out for reuse
    /// elsewhere.
    function mul512(uint256 a, uint256 b) private pure returns (uint256 high, uint256 low) {
        // 512-bit multiply [high low] = x * y. Compute the product mod 2²⁵⁶ and mod 2²⁵⁶ - 1, then use
        // the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
        // variables such that product = high * 2²⁵⁶ + low.
        assembly ("memory-safe") {
            let mm := mulmod(a, b, not(0))
            low := mul(a, b)
            high := sub(sub(mm, low), lt(mm, low))
        }
    }

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
    function minus(int256 signedCoefficient, int256 exponent) private pure returns (int256, int256) {
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
}
