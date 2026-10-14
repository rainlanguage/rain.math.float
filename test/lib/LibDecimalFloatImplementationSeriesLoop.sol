// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    POW_FIXED_ONE,
    POW_FIXED_LN10,
    POW_FIXED_ONE_ODD_INVERSE,
    LOG10_RATIO_Z_MAX
} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {
    Exp10FixedOutOfRange,
    Log10RatioOutOfRange,
    Log10RatioRelativeSumTooSmall,
    MulDivOverflow
} from "../../src/error/ErrDecimalFloat.sol";

/// `mulDivFixedUnguarded`, `log10Ratio` and `exp10Fixed` verbatim from
/// `src/lib/implementation/LibDecimalFloatImplementation.sol` at 9d843e7,
/// before their multiplies were written out in place, with the helpers they
/// call copied from the same commit, so they call nothing on the live library.
/// Equivalence tests only.
/// EQUIVALENCE BASELINE ONLY, NEVER A VALUE ORACLE: agreeing with it says
/// nothing about a value. Expected values come from `LibExactFloat`.
library LibDecimalFloatImplementationSeriesMain {
    function mulDivFixedUnguarded(uint256 x, uint256 y) private pure returns (uint256 result) {
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

    function log10Ratio(uint256 a, uint256 b, bool relative) internal pure returns (int256, int256) {
        bool below = a < b;
        uint256 difference = below ? b - a : a - b;
        uint256 sum;
        unchecked {
            sum = a + b;
        }
        uint256 z;
        int256 exponent = -50;
        if (relative) {
            // sum is below a only by wrapping past 2^256.
            if (sum < a) {
                revert Log10RatioOutOfRange(a, b);
            }
            if (sum < POW_FIXED_ONE) {
                revert Log10RatioRelativeSumTooSmall(a, b);
            }
            z = mulDiv(difference, POW_FIXED_ONE, sum);
            if (z > LOG10_RATIO_Z_MAX) {
                revert Log10RatioOutOfRange(a, b);
            }
            // Scale the difference by the largest power of ten that keeps it
            // within int256.max, as maximizeFull does.
            unchecked {
                if (difference != 0) {
                    if (difference <= uint256(type(int256).max) / 1e64) {
                        difference *= 1e64;
                        exponent -= 64;
                    }
                    if (difference <= uint256(type(int256).max) / 1e32) {
                        difference *= 1e32;
                        exponent -= 32;
                    }
                    if (difference <= uint256(type(int256).max) / 1e16) {
                        difference *= 1e16;
                        exponent -= 16;
                    }
                    if (difference <= uint256(type(int256).max) / 1e8) {
                        difference *= 1e8;
                        exponent -= 8;
                    }
                    if (difference <= uint256(type(int256).max) / 1e4) {
                        difference *= 1e4;
                        exponent -= 4;
                    }
                    if (difference <= uint256(type(int256).max) / 1e2) {
                        difference *= 1e2;
                        exponent -= 2;
                    }
                    if (difference <= uint256(type(int256).max) / 10) {
                        difference *= 10;
                        exponent -= 1;
                    }
                }
            }
        } else {
            // sum is at most a by wrapping past 2^256 or for b of zero.
            if (sum <= a) {
                revert Log10RatioOutOfRange(a, b);
            }
            z = mulDiv(difference, POW_FIXED_ONE, sum);
            if (z > LOG10_RATIO_Z_MAX) {
                revert Log10RatioOutOfRange(a, b);
            }
        }
        uint256 zSquared = mulDivFixedUnguarded(z, z);
        // atanh(z) / z
        uint256 series = POW_FIXED_ONE;
        uint256 term = POW_FIXED_ONE;
        for (uint256 k = 3; term > 0; k += 2) {
            term = mulDivFixedUnguarded(term, zSquared);
            series += term / k;
        }
        // The scaled series is below 0.8686e50, so the quotient is below it
        // when not relative, and below int256.max / 1e50 times it when
        // relative, as a + b is at least 1e50.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedCoefficient = int256(mulDiv(difference, mulDiv(series, 2 * POW_FIXED_ONE, POW_FIXED_LN10), sum));
        return (below ? -signedCoefficient : signedCoefficient, exponent);
    }

    function exp10Fixed(uint256 x) internal pure returns (uint256 result) {
        if (x >= POW_FIXED_ONE) {
            revert Exp10FixedOutOfRange(x);
        }
        unchecked {
            result = POW_FIXED_ONE;
            if (x >= 5e49) {
                x -= 5e49;
                result = 316227766016837933199889354443271853371955513932521;
            }
            if (x >= 2.5e49) {
                x -= 2.5e49;
                result = mulDivFixedUnguarded(result, 177827941003892280122542119519268484473579052640225);
            }
            if (x >= 1.25e49) {
                x -= 1.25e49;
                result = mulDivFixedUnguarded(result, 133352143216332402567593171529533109241566796476437);
            }
            if (x >= 6.25e48) {
                x -= 6.25e48;
                result = mulDivFixedUnguarded(result, 115478198468945817966648288729550828156694804147961);
            }
            if (x >= 3.125e48) {
                x -= 3.125e48;
                result = mulDivFixedUnguarded(result, 107460782832131749721594153196434359466719822837527);
            }
            if (x >= 1.5625e48) {
                x -= 1.5625e48;
                result = mulDivFixedUnguarded(result, 103663292843769799729165172492534446770887303110100);
            }
            if (x >= 7.8125e47) {
                x -= 7.8125e47;
                result = mulDivFixedUnguarded(result, 101815172171818184147422688857883534761587963866759);
            }
            if (x >= 3.90625e47) {
                x -= 3.90625e47;
                result = mulDivFixedUnguarded(result, 100903504484144743775925442390642133138116897958823);
            }
            if (x >= 1.953125e47) {
                x -= 1.953125e47;
                result = mulDivFixedUnguarded(result, 100450736425446251566479469434131766413696548644885);
            }
            if (x >= 9.765625e46) {
                x -= 9.765625e46;
                result = mulDivFixedUnguarded(result, 100225114829291291546567363886657119245424113020822);
            }
            if (x >= 4.8828125e46) {
                x -= 4.8828125e46;
                result = mulDivFixedUnguarded(result, 100112494139987987588542643436571177327133841887328);
            }
            if (x >= 2.44140625e46) {
                x -= 2.44140625e46;
                result = mulDivFixedUnguarded(result, 100056231260220863661851136780963697869649047983110);
            }
            if (x >= 1.220703125e46) {
                x -= 1.220703125e46;
                result = mulDivFixedUnguarded(result, 100028111678778013239925736576968704561701000407571);
            }
            if (x >= 6.103515625e45) {
                x -= 6.103515625e45;
                result = mulDivFixedUnguarded(result, 100014054851694725816277118785892892480765770706773);
            }
            if (x >= 3.0517578125e45) {
                x -= 3.0517578125e45;
                result = mulDivFixedUnguarded(result, 100007027178941143553881363867653576320883673909194);
            }
            if (x >= 1.52587890625e45) {
                x -= 1.52587890625e45;
                result = mulDivFixedUnguarded(result, 100003513527746185660858233586155663318996214797054);
            }
            uint256 series = 501392883377544009807090987164215453583108663277;
            series = 1959769462647852369682789087147690310674843760584 + mulDivFixedUnguarded(series, x);
            series = 6808936507443706236540404026537606122629959236393 + mulDivFixedUnguarded(series, x);
            series = 20699584869686809669966601589738494188245922773010 + mulDivFixedUnguarded(series, x);
            series = 53938292919558141019969155571017253478007614081814 + mulDivFixedUnguarded(series, x);
            series = 117125514891226696317825761603265234076100689858139 + mulDivFixedUnguarded(series, x);
            series = 203467859229347619683099119171381053024105502647771 + mulDivFixedUnguarded(series, x);
            series = 265094905523919900528083319429700884579872503956640 + mulDivFixedUnguarded(series, x);
            series = POW_FIXED_LN10 + mulDivFixedUnguarded(series, x);
            series = POW_FIXED_ONE + mulDivFixedUnguarded(series, x);
            result = mulDivFixedUnguarded(result, series);
        }
    }

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
}
