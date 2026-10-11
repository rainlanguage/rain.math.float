// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    LibDecimalFloatImplementation,
    POW_FIXED_ONE,
    POW_FIXED_LN10,
    POW_FIXED_SQRT_ONE,
    POW_FIXED_TWO_SQRT_ONE,
    POW_FIXED_ONE_ODD_INVERSE
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Log10RatioRelativeSumTooSmall} from "src/error/ErrDecimalFloat.sol";

/// `log10Ratio` as at 5210e11, the #336 head, before the relative path scaled
/// by a cascade, with the series written out in place as it is now, so the
/// equivalence tests compare the scaling alone. The helpers it calls are
/// called on the live library. Equivalence tests only.
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
            z = LibDecimalFloatImplementation.mulDiv(difference, POW_FIXED_ONE, sum);
            // difference is below 1e76 so it fits and maximizes in place.
            // forge-lint: disable-next-item(unsafe-typecast)
            (int256 differenceCoefficient, int256 differenceExponent) =
                LibDecimalFloatImplementation.maximizeFull(int256(difference), 0);
            // forge-lint: disable-next-line(unsafe-typecast)
            difference = uint256(differenceCoefficient);
            exponent += differenceExponent;
        } else {
            z = LibDecimalFloatImplementation.mulDiv(difference, POW_FIXED_ONE, sum);
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
        int256 signedCoefficient = int256(
            LibDecimalFloatImplementation.mulDiv(
                difference, LibDecimalFloatImplementation.mulDiv(series, 2 * POW_FIXED_ONE, POW_FIXED_LN10), sum
            )
        );
        return (below ? -signedCoefficient : signedCoefficient, exponent);
    }
    // slither-disable-end divide-before-multiply
}
