// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibDecimalFloatImplementation} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {MulDivOverflow, SqrtOutOfRange} from "../../src/error/ErrDecimalFloat.sol";

/// Variants of `LibDecimalFloatImplementation.sqrt`, for equivalence and gas
/// comparison only.
/// EQUIVALENCE BASELINE ONLY, NEVER A VALUE ORACLE: agreeing with it says
/// nothing about a value. Expected values come from `LibExactFloat`.
library LibDecimalFloatSqrtVariants {
    /// The integer sqrt verbatim from 0a8065d and 7459101 on #309's branch, its
    /// residual compared in 512 bits, calling the private `mulDiv` and
    /// `mul512` copied from those commits.
    function sqrtPr309(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        unchecked {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 coefficient = uint256(signedCoefficient);
            if (coefficient < 1e75) {
                if (coefficient < 1e38) {
                    coefficient *= 1e38;
                    exponent -= 38;
                }
                if (coefficient < 1e57) {
                    coefficient *= 1e19;
                    exponent -= 19;
                }
                if (coefficient < 1e66) {
                    coefficient *= 1e10;
                    exponent -= 10;
                }
                if (coefficient < 1e71) {
                    coefficient *= 1e5;
                    exponent -= 5;
                }
                if (coefficient < 1e73) {
                    coefficient *= 1e3;
                    exponent -= 3;
                }
                if (coefficient < 1e74) {
                    coefficient *= 1e2;
                    exponent -= 2;
                }
                if (coefficient < 1e75) {
                    coefficient *= 10;
                    exponent -= 1;
                }
            }
            uint256 scale;
            uint256 estimate;
            uint256 estimateScale;
            bool odd = exponent & 1 == 1;
            if (coefficient < 1e76) {
                (scale, estimate, estimateScale) = odd ? (1e5, coefficient / 10, 1e3) : (1e6, coefficient, 1e3);
            } else {
                (scale, estimate, estimateScale) = odd ? (1e5, coefficient / 10, 1e3) : (1e4, coefficient, 1e2);
            }
            exponent = (exponent - (odd ? int256(5) : (coefficient < 1e76 ? int256(6) : int256(4)))) / 2;
            uint256 root;
            assembly ("memory-safe") {
                root := add(shr(1, shr(125, estimate)), shl(124, 1))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := sub(root, gt(root, div(estimate, root)))
            }
            root = (root + 2) * estimateScale;
            root = (root + mulDiv(coefficient, scale, root)) >> 1;
            (uint256 high, uint256 low) = mul512(coefficient, scale);
            (uint256 rootHigh, uint256 rootLow) = mul512(root, root);
            if (rootHigh > high || (rootHigh == high && rootLow > low)) {
                root -= 1;
                (rootHigh, rootLow) = mul512(root, root);
            }
            assembly ("memory-safe") {
                let differenceLow := sub(low, rootLow)
                let differenceHigh := sub(sub(high, rootHigh), lt(low, rootLow))
                root := add(root, or(gt(differenceHigh, 0), gt(differenceLow, root)))
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            return (int256(root), exponent);
        }
    }

    /// The library's sqrt before #359, comments dropped: 2^125 seeds seven
    /// Newton steps over E. Verbatim from
    /// `src/lib/implementation/LibDecimalFloatImplementation.sol` at
    /// 26a3cf068ebf6c5bb418744f62abfe4be95b1fc7, calling the private
    /// `scaleUp`, `mulDiv` and `mul512` copied from that commit.
    /// Like the copied `scaleUp`, it does not check its domain: outside a
    /// coefficient in (0, 1e76) and an exponent of at least
    /// `type(int256).min + 75`, it returns what 26a3cf06 returned, where the
    /// live sqrt reverts.
    function sqrtPre359(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
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

    /// The library's sqrt with its Newton iterations in plain Solidity.
    /// Not frozen: it shares the live `mulDiv`, so it differs from the library only in its named step.
    function sqrtPlainNewton(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        int256 inputExponent = exponent;
        unchecked {
            // forge-lint: disable-next-line(unsafe-typecast)
            if (uint256(signedCoefficient) - 1 >= 1e76 - 1) {
                revert SqrtOutOfRange(signedCoefficient, exponent);
            }
        }
        (signedCoefficient, exponent) = scaleUpUnguarded(signedCoefficient, exponent);
        unchecked {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 coefficient = uint256(signedCoefficient);
            uint256 scale = 1e6;
            uint256 estimate = coefficient;
            uint256 root = coefficient / 12e37 + 26e36;
            if (exponent & 1 == 1) {
                scale = 1e5;
                estimate = coefficient / 10;
                root = estimate / 38e36 + 82e35;
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            exponent -= scale == 1e5 ? int256(5) : int256(6);
            assembly ("memory-safe") {
                exponent := xor(sar(1, exponent), shl(255, sgt(exponent, inputExponent)))
            }
            root = (root + estimate / root) >> 1;
            root = (root + estimate / root) >> 1;
            root = (root + estimate / root) >> 1;
            root = (root + estimate / root) >> 1;
            root *= 1e3;
            root = (root + LibDecimalFloatImplementation.mulDiv(coefficient, scale, root)) >> 1;
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

    /// The library's sqrt with its residual rounding in assembly.
    /// Not frozen: it shares the live `mulDiv`, so it differs from the library only in its named step.
    function sqrtAsmResidual(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        int256 inputExponent = exponent;
        unchecked {
            // forge-lint: disable-next-line(unsafe-typecast)
            if (uint256(signedCoefficient) - 1 >= 1e76 - 1) {
                revert SqrtOutOfRange(signedCoefficient, exponent);
            }
        }
        (signedCoefficient, exponent) = scaleUpUnguarded(signedCoefficient, exponent);
        unchecked {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 coefficient = uint256(signedCoefficient);
            uint256 scale = 1e6;
            uint256 estimate = coefficient;
            uint256 root = coefficient / 12e37 + 26e36;
            if (exponent & 1 == 1) {
                scale = 1e5;
                estimate = coefficient / 10;
                root = estimate / 38e36 + 82e35;
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            exponent -= scale == 1e5 ? int256(5) : int256(6);
            assembly ("memory-safe") {
                exponent := xor(sar(1, exponent), shl(255, sgt(exponent, inputExponent)))
            }
            assembly ("memory-safe") {
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
            }
            root *= 1e3;
            root = (root + LibDecimalFloatImplementation.mulDiv(coefficient, scale, root)) >> 1;
            assembly ("memory-safe") {
                let residual := sub(mul(coefficient, scale), mul(root, root))
                root := add(root, sgt(residual, root))
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            return (int256(root), exponent);
        }
    }

    /// The library's sqrt with its low-word residual rounding replaced by
    /// `sqrtPr309`'s 512-bit residual compare.
    /// Not frozen: it shares the live `mulDiv` and `mul512`, so it differs from the library only in its named step.
    function sqrt512Residual(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        int256 inputExponent = exponent;
        unchecked {
            // forge-lint: disable-next-line(unsafe-typecast)
            if (uint256(signedCoefficient) - 1 >= 1e76 - 1) {
                revert SqrtOutOfRange(signedCoefficient, exponent);
            }
        }
        (signedCoefficient, exponent) = scaleUpUnguarded(signedCoefficient, exponent);
        unchecked {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 coefficient = uint256(signedCoefficient);
            uint256 scale = 1e6;
            uint256 estimate = coefficient;
            uint256 root = coefficient / 12e37 + 26e36;
            if (exponent & 1 == 1) {
                scale = 1e5;
                estimate = coefficient / 10;
                root = estimate / 38e36 + 82e35;
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            exponent -= scale == 1e5 ? int256(5) : int256(6);
            assembly ("memory-safe") {
                exponent := xor(sar(1, exponent), shl(255, sgt(exponent, inputExponent)))
            }
            assembly ("memory-safe") {
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
                root := shr(1, add(root, div(estimate, root)))
            }
            root *= 1e3;
            root = (root + LibDecimalFloatImplementation.mulDiv(coefficient, scale, root)) >> 1;
            (uint256 high, uint256 low) = LibDecimalFloatImplementation.mul512(coefficient, scale);
            (uint256 rootHigh, uint256 rootLow) = LibDecimalFloatImplementation.mul512(root, root);
            if (rootHigh > high || (rootHigh == high && rootLow > low)) {
                root -= 1;
                (rootHigh, rootLow) = LibDecimalFloatImplementation.mul512(root, root);
            }
            assembly ("memory-safe") {
                let differenceLow := sub(low, rootLow)
                let differenceHigh := sub(sub(high, rootHigh), lt(low, rootLow))
                root := add(root, or(gt(differenceHigh, 0), gt(differenceLow, root)))
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            return (int256(root), exponent);
        }
    }

    /// Scales a coefficient in (0, 1e75) up into [1e75, 1e76), lowering the
    /// exponent by the at most 75 digits of the shift.
    /// @param signedCoefficient The signed coefficient, in (0, 1e75).
    /// @param exponent The exponent, at least `type(int256).min + 75`.
    /// @return signedCoefficient The scaled coefficient.
    /// @return exponent The exponent of the scaled coefficient.
    function scaleUp(int256 signedCoefficient, int256 exponent) private pure returns (int256, int256) {
        unchecked {
            // Each step multiplies by 10^s only when c < 10^(76 - s), so c
            // stays below 1e76, and leaves c at least 10^(76 - s). That holds
            // as the previous step left c at least 10^(76 - 2s) (c >= 1 for
            // the first): s is half, rounded up, of the 76, 38, 19, 10, 5, 3
            // and 2 digits c may lack to reach 1e76, so c ends at least 1e75.
            // c gains exactly the digits shifted, under 76 from c >= 1.
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

    /// The library's private `scaleUpUnguarded`, verbatim, as the library's
    /// `sqrt` calls it.
    function scaleUpUnguarded(int256 signedCoefficient, int256 exponent) private pure returns (int256, int256) {
        unchecked {
            // Each step multiplies by 10^s only when c < 10^(76 - s), so c
            // stays below 1e76, and leaves c at least 10^(76 - s). That holds
            // as the previous step left c at least 10^(76 - 2s) (c >= 1 for
            // the first): s is half, rounded up, of the 76, 38, 19, 10, 5, 3
            // and 2 digits c may lack to reach 1e76, so c ends at least 1e75.
            // c gains exactly the digits shifted, under 76 from c >= 1.
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
}
