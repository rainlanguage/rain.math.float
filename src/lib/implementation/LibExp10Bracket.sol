// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev Limb base of the bracket arithmetic. A limb product plus two limbs is
/// below 1e76 and so fits 256 bits.
uint256 constant BRACKET_LIMB = 1e38;

/// @dev Limbs after the point at the first precision tried.
uint256 constant BRACKET_START_LIMBS = 2;

/// @dev Halvings of the exponent before its Taylor series.
uint256 constant BRACKET_HALVINGS = 8;

/// Decides which side of a decimal r the value 10^s falls, for the rounding tie
/// that log10 and pow10 cannot resolve in 1e50 fixed point.
///
/// Numbers are little endian arrays of base 1e38 limbs, fixed point with L
/// limbs after the point and one before it. Each step rounds down or up so that
/// a lower and an upper bound enclose the true value, and the comparison is
/// decided when the bounds fall on one side of r. Otherwise L doubles. The
/// width of the bounds falls as 1e-38L, and 10^s is irrational for every
/// non-integer decimal s, so it never equals r and the loop ends.
library LibExp10Bracket {
    /// Whether 10^s < r, where s is g, or -g when `negative`, for
    /// g = gCoefficient 10^gExponent in (0, 1), and r = rCoefficient 10^rExponent
    /// in [1, 10) for positive s, in [0.1, 1) for negative s.
    function below(uint256 gCoefficient, int256 gExponent, bool negative, uint256 rCoefficient, int256 rExponent)
        internal
        pure
        returns (bool)
    {
        for (uint256 limbs = BRACKET_START_LIMBS;; limbs *= 2) {
            (bool decided, bool result) = belowAt(gCoefficient, gExponent, negative, rCoefficient, rExponent, limbs);
            if (decided) {
                return result;
            }
        }
    }

    /// `below` at one precision, or `decided` false when the bounds straddle r.
    function belowAt(
        uint256 gCoefficient,
        int256 gExponent,
        bool negative,
        uint256 rCoefficient,
        int256 rExponent,
        uint256 limbs
    ) internal pure returns (bool decided, bool result) {
        (uint256[] memory low, uint256[] memory high) = exp10(gCoefficient, gExponent, limbs);
        (uint256[] memory rLow, uint256[] memory rHigh) = bounds(rCoefficient, rExponent, limbs);
        if (!negative) {
            if (compare(high, rLow) < 0) {
                return (true, true);
            }
            if (compare(low, rHigh) > 0) {
                return (true, false);
            }
            return (false, false);
        }
        // 10^-g < r exactly when r 10^g > 1.
        uint256[] memory one = new uint256[](limbs + 1);
        one[limbs] = 1;
        if (compare(mul(rLow, low, limbs, false), one) > 0) {
            return (true, true);
        }
        if (compare(mul(rHigh, high, limbs, true), one) < 0) {
            return (true, false);
        }
        return (false, false);
    }

    /// Bounds on 10^g for g in [gLow, gHigh], g at most 1.
    ///
    /// y = g ln 10 / 2^8 is at most 0.009, so the Taylor series of e^y loses
    /// under 1.01 units per term to its floors, each floor's unit plus 0.009 of
    /// the previous term's loss, and under 1.02 units to the terms it drops once
    /// a term floors to zero. The upper bound adds two units per term and two
    /// more. Squaring eight times with floors and ceilings keeps the bounds.
    function exp10(uint256 gCoefficient, int256 gExponent, uint256 limbs)
        internal
        pure
        returns (uint256[] memory low, uint256[] memory high)
    {
        (uint256[] memory gLow, uint256[] memory gHigh) = bounds(gCoefficient, gExponent, limbs);
        (uint256[] memory lnLow, uint256[] memory lnHigh) = ln10(limbs);
        uint256 terms;
        (low,) = expSeries(divSmall(mul(gLow, lnLow, limbs, false), 1 << BRACKET_HALVINGS, false), limbs);
        (high, terms) = expSeries(divSmall(mul(gHigh, lnHigh, limbs, true), 1 << BRACKET_HALVINGS, true), limbs);
        addSmall(high, 2 * terms + 2);
        for (uint256 i = 0; i < BRACKET_HALVINGS; i++) {
            low = mul(low, low, limbs, false);
            high = mul(high, high, limbs, true);
        }
    }

    /// The Taylor series of e^y with every step floored, and the number of
    /// terms taken.
    function expSeries(uint256[] memory y, uint256 limbs) internal pure returns (uint256[] memory sum, uint256 terms) {
        sum = new uint256[](limbs + 1);
        sum[limbs] = 1;
        uint256[] memory term = copy(sum);
        for (uint256 n = 1;; n++) {
            term = divSmall(mul(term, y, limbs, false), n, false);
            terms++;
            if (isZero(term)) {
                return (sum, terms);
            }
            add(sum, term);
        }
    }

    /// Bounds on ln 10 = 46 atanh(1/31) + 34 atanh(1/49) + 20 atanh(1/161).
    function ln10(uint256 limbs) internal pure returns (uint256[] memory low, uint256[] memory high) {
        (uint256[] memory a31, uint256 slack31) = atanhInverse(31, limbs);
        (uint256[] memory a49, uint256 slack49) = atanhInverse(49, limbs);
        (uint256[] memory a161, uint256 slack161) = atanhInverse(161, limbs);
        low = mulSmall(a31, 46);
        add(low, mulSmall(a49, 34));
        add(low, mulSmall(a161, 20));
        high = copy(low);
        addSmall(high, 46 * slack31 + 34 * slack49 + 20 * slack161);
    }

    /// atanh(1/n) = sum 1 / ((2k + 1) n^(2k + 1)), floored, and a slack that
    /// the floored sum is within.
    ///
    /// Floors of floors of integer quotients are the floor of the whole
    /// quotient, so each term is its exact value floored and loses under a
    /// unit. The terms stop where n^-(2k + 1) is below a unit, which leaves a
    /// tail under 1 / (1 - n^-2) / (2k + 1), under a unit.
    function atanhInverse(uint256 n, uint256 limbs) internal pure returns (uint256[] memory sum, uint256 slack) {
        sum = new uint256[](limbs + 1);
        uint256[] memory power = new uint256[](limbs + 1);
        power[limbs] = 1;
        power = divSmall(power, n, false);
        uint256 nSquared = n * n;
        for (uint256 k = 1; !isZero(power); k += 2) {
            add(sum, divSmall(power, k, false));
            slack++;
            power = divSmall(power, nSquared, false);
        }
        slack++;
    }

    /// coefficient 10^exponent in fixed point, floored and ceiled.
    function bounds(uint256 coefficient, int256 exponent, uint256 limbs)
        internal
        pure
        returns (uint256[] memory low, uint256[] memory high)
    {
        bool inexact;
        (low, inexact) = fromDecimal(coefficient, exponent, limbs);
        high = copy(low);
        if (inexact) {
            addSmall(high, 1);
        }
    }

    /// coefficient 10^exponent in fixed point, floored, and whether the floor
    /// dropped anything. The value is below 10.
    function fromDecimal(uint256 coefficient, int256 exponent, uint256 limbs)
        internal
        pure
        returns (uint256[] memory value, bool inexact)
    {
        value = new uint256[](limbs + 1);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 shift = exponent + int256(38 * limbs);
        if (shift < 0) {
            if (shift < -77) {
                return (value, coefficient != 0);
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 scale = 10 ** uint256(-shift);
            inexact = coefficient % scale != 0;
            coefficient /= scale;
            shift = 0;
        }
        // shift is not negative here.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 limbShift = uint256(shift) / 38;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 digits = uint256(shift) % 38;
        // A value below 10 has no limb above `limbs`, so the coefficient's
        // three limbs fit under any shift that keeps it below 10.
        for (uint256 i = 0; coefficient > 0; i++) {
            value[i + limbShift] = coefficient % BRACKET_LIMB;
            coefficient /= BRACKET_LIMB;
        }
        if (digits > 0) {
            value = mulSmall(value, 10 ** digits);
        }
    }

    function copy(uint256[] memory a) internal pure returns (uint256[] memory b) {
        b = new uint256[](a.length);
        for (uint256 i = 0; i < a.length; i++) {
            b[i] = a[i];
        }
    }

    function isZero(uint256[] memory a) internal pure returns (bool) {
        for (uint256 i = 0; i < a.length; i++) {
            if (a[i] != 0) {
                return false;
            }
        }
        return true;
    }

    /// -1, 0 or 1 as a is below, equal to or above b.
    function compare(uint256[] memory a, uint256[] memory b) internal pure returns (int256) {
        for (uint256 i = a.length; i > 0; i--) {
            if (a[i - 1] != b[i - 1]) {
                return a[i - 1] < b[i - 1] ? int256(-1) : int256(1);
            }
        }
        return 0;
    }

    /// a += b.
    function add(uint256[] memory a, uint256[] memory b) internal pure {
        uint256 carry = 0;
        for (uint256 i = 0; i < a.length; i++) {
            uint256 limb = a[i] + b[i] + carry;
            carry = limb / BRACKET_LIMB;
            a[i] = limb % BRACKET_LIMB;
        }
    }

    /// a += small, for small below 1e38.
    function addSmall(uint256[] memory a, uint256 small) internal pure {
        for (uint256 i = 0; small > 0; i++) {
            uint256 limb = a[i] + small;
            small = limb / BRACKET_LIMB;
            a[i] = limb % BRACKET_LIMB;
        }
    }

    /// a small, for small below 1e38.
    function mulSmall(uint256[] memory a, uint256 small) internal pure returns (uint256[] memory product) {
        product = new uint256[](a.length);
        uint256 carry = 0;
        for (uint256 i = 0; i < a.length; i++) {
            uint256 limb = a[i] * small + carry;
            carry = limb / BRACKET_LIMB;
            product[i] = limb % BRACKET_LIMB;
        }
    }

    /// a / small, floored or ceiled, for small at most 1e38.
    function divSmall(uint256[] memory a, uint256 small, bool up) internal pure returns (uint256[] memory quotient) {
        quotient = new uint256[](a.length);
        uint256 remainder = 0;
        for (uint256 i = a.length; i > 0; i--) {
            uint256 limb = remainder * BRACKET_LIMB + a[i - 1];
            quotient[i - 1] = limb / small;
            remainder = limb % small;
        }
        if (up && remainder != 0) {
            addSmall(quotient, 1);
        }
    }

    /// a b in fixed point, floored or ceiled. The product is below 1e38.
    function mul(uint256[] memory a, uint256[] memory b, uint256 limbs, bool up)
        internal
        pure
        returns (uint256[] memory result)
    {
        uint256 length = a.length;
        uint256[] memory product = new uint256[](2 * length);
        for (uint256 i = 0; i < length; i++) {
            uint256 carry = 0;
            for (uint256 j = 0; j < length; j++) {
                uint256 limb = a[i] * b[j] + product[i + j] + carry;
                carry = limb / BRACKET_LIMB;
                product[i + j] = limb % BRACKET_LIMB;
            }
            product[i + length] = carry;
        }
        result = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = product[i + limbs];
        }
        if (up) {
            for (uint256 i = 0; i < limbs; i++) {
                if (product[i] != 0) {
                    addSmall(result, 1);
                    break;
                }
            }
        }
    }
}
