// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {ExponentOverflow, MulDivOverflow} from "src/error/ErrDecimalFloat.sol";
import {
    MAXIMIZED_ZERO_SIGNED_COEFFICIENT,
    MAXIMIZED_ZERO_EXPONENT
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

/// `mul` and its two cold helpers verbatim from
/// `src/lib/implementation/LibDecimalFloatImplementation.sol` at
/// 26cd9e8ffd313d55e37a3e3eabccbfc33016874a, before the packed-exponent fast
/// path, with the helpers it calls copied from the same commit, so it calls
/// nothing on the live library. EQUIVALENCE BASELINE ONLY, NEVER A VALUE
/// ORACLE: it copies the old steps, so agreeing with it says nothing about a
/// value. Expected values come from `LibExactFloat` over exact math.
library LibDecimalFloatImplementationMulPr307 {
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
            if (exponentB < 0) {
                if (exponent > exponentA) {
                    return mulExponentBelowFloor(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
                }
            } else if (exponent < exponentA) {
                return mulExponentNearCeiling(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
            }
            // The lift below adds at most 77 and `unabsUnsignedMulOrDivLossy`
            // at most 1.
            if (exponent > type(int256).max - 78) {
                return mulExponentNearCeiling(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
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
                mulDiv(signedCoefficientAAbs, signedCoefficientBAbs, uint256(10) ** adjustExponent),
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
}
