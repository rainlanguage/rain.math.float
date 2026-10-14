// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    MAXIMIZED_ZERO_SIGNED_COEFFICIENT,
    MAXIMIZED_ZERO_EXPONENT,
    POW_FIXED_ONE,
    POW_FIXED_LN10,
    POW_FIXED_SQRT_ONE,
    POW_FIXED_TWO_SQRT_ONE,
    POW_FIXED_ONE_ODD_INVERSE
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Log10RatioRelativeSumTooSmall, MaximizeOverflow, MulDivOverflow} from "src/error/ErrDecimalFloat.sol";

/// `log10Ratio` as at 5210e11, the #336 head, before the relative path scaled
/// by a cascade, with the series written out in place as it is now, so the
/// equivalence tests compare the scaling alone. The helpers it calls are
/// copied from 5210e11, so it calls nothing on the live library. Equivalence
/// tests only.
/// EQUIVALENCE BASELINE ONLY, NEVER A VALUE ORACLE: agreeing with it says
/// nothing about a value. Expected values come from `LibExactFloat`.
library LibDecimalFloatImplementationLog10RatioPr336 {
    // slither-disable-start divide-before-multiply
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
            // forge-lint: disable-next-item(unsafe-typecast)
            (int256 differenceCoefficient, int256 differenceExponent) = maximizeFull(int256(difference), 0);
            // forge-lint: disable-next-line(unsafe-typecast)
            difference = uint256(differenceCoefficient);
            exponent += differenceExponent;
        } else {
            z = mulDiv(difference, POW_FIXED_ONE, sum);
        }
        uint256 series;
        uint256 inverse = POW_FIXED_ONE_ODD_INVERSE;
        assembly ("memory-safe") {
            // floor(z^2 / 1e50) exactly, as u^2 + floor((2 u v 1e25 + v^2) /
            // 1e50) for z = u 1e25 + v. z is at most 1e50, so u is at most 1e25
            // and the dividend is under 2e75 + 1e50, which fits a word.
            let u := div(z, POW_FIXED_SQRT_ONE)
            let v := mod(z, POW_FIXED_SQRT_ONE)
            let zSquared := add(mul(u, u), div(add(mul(mul(u, v), POW_FIXED_TWO_SQRT_ONE), mul(v, v)), POW_FIXED_ONE))
            series := add(POW_FIXED_ONE, div(zSquared, 3))
            // z^4 and z^6 times zSquared can pass 2^256, so these two are
            // `mulDivFixed` in place: mm and prod0 give the product's high
            // word (with borrow) and low word. Subtracting
            // the remainder mod 1e50 makes it an exact multiple of 1e50 =
            // 2^50 5^50, so shifting 50 bits across both words divides by
            // 2^50 and multiplying by 5^50's inverse mod 2^256 divides by
            // 5^50 exactly.
            let mm := mulmod(zSquared, zSquared, not(0))
            let prod0 := mul(zSquared, zSquared)
            let remainder := mulmod(zSquared, zSquared, POW_FIXED_ONE)
            let term :=
                mul(
                    or(
                        shr(50, sub(prod0, remainder)),
                        shl(206, sub(sub(sub(mm, prod0), lt(mm, prod0)), gt(remainder, prod0)))
                    ),
                    inverse
                )
            series := add(series, div(term, 5))
            mm := mulmod(term, zSquared, not(0))
            prod0 := mul(term, zSquared)
            remainder := mulmod(term, zSquared, POW_FIXED_ONE)
            term := mul(
                or(
                    shr(50, sub(prod0, remainder)),
                    shl(206, sub(sub(sub(mm, prod0), lt(mm, prod0)), gt(remainder, prod0)))
                ),
                inverse
            )
            series := add(series, div(term, 7))
            // term is now below z^6, so term * zSquared fits a word.
            term := div(mul(term, zSquared), POW_FIXED_ONE)
            series := add(series, div(term, 9))
            term := div(mul(term, zSquared), POW_FIXED_ONE)
            series := add(series, div(term, 11))
            term := div(mul(term, zSquared), POW_FIXED_ONE)
            series := add(series, div(term, 13))
            term := div(mul(term, zSquared), POW_FIXED_ONE)
            series := add(series, div(term, 15))
        }
        // The scaled series is below 0.8686e50, so the quotient is below it
        // when not relative, and below int256.max / 1e50 times it when
        // relative, as a + b is at least 1e50.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedCoefficient = int256(mulDiv(difference, mulDiv(series, 2 * POW_FIXED_ONE, POW_FIXED_LN10), sum));
        return (below ? -signedCoefficient : signedCoefficient, exponent);
    }

    // slither-disable-end divide-before-multiply

    // The helpers the copies above call, verbatim from the same commit, so
    // this baseline calls nothing on the live library.

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

    /// Maximizes a float as per `maximize` but errors if the exponent cannot
    /// take the whole shift. This is analogous to other functions in the lib
    /// that are "lossless".
    /// @param signedCoefficient The signed coefficient.
    /// @param exponent The exponent.
    /// @return signedCoefficient The maximized signed coefficient.
    /// @return exponent The maximized exponent.
    function maximizeFull(int256 signedCoefficient, int256 exponent) private pure returns (int256, int256) {
        (int256 trySignedCoefficient, int256 tryExponent, int256 shortfall) = maximize(signedCoefficient, exponent);
        if (shortfall != 0) {
            revert MaximizeOverflow(signedCoefficient, exponent);
        }
        return (trySignedCoefficient, tryExponent);
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
    function maximize(int256 signedCoefficient, int256 exponent) private pure returns (int256, int256, int256) {
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
}
