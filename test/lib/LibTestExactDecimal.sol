// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";
import {NegativeFixedDecimalConversion, FixedDecimalOverflow} from "src/error/ErrDecimalFloat.sol";

/// An unsigned integer below 2^512.
struct U512 {
    uint256 hi;
    uint256 lo;
}

/// Exact decimal comparisons, independent of the library under test. Values
/// are `magnitude × 10^exponent` with a 512 bit magnitude, and every
/// comparison is decided in exact integer arithmetic.
library LibTestExactDecimal {
    /// A result packs iff the magnitude of its floor at `10^int32.max` is at
    /// most `2^223 + 1`: that far past the int224 bound of its sign, shedding a
    /// digit would land below the bound, so it takes the bound (#332). Either
    /// sign overflows from `(2^223 + 2) × 10^int32.max` up in magnitude.
    uint256 internal constant OVERFLOW_FLOOR = 2 ** 223 + 2;

    function u512(uint256 x) internal pure returns (U512 memory) {
        return U512(0, x);
    }

    function mul(uint256 a, uint256 b) internal pure returns (U512 memory) {
        (uint256 hi, uint256 lo) = Math.mul512(a, b);
        return U512(hi, lo);
    }

    /// Checked: a product at or above 2^512 panics rather than wrapping.
    function mulSmall(U512 memory x, uint256 m) internal pure returns (U512 memory) {
        (uint256 carry, uint256 lo) = Math.mul512(x.lo, m);
        return U512(x.hi * m + carry, lo);
    }

    function mulPow10(U512 memory x, uint256 k) internal pure returns (U512 memory) {
        for (uint256 i = 0; i < k; i++) {
            x = mulSmall(x, 10);
        }
        return x;
    }

    /// Checked: a sum at or above 2^512 panics rather than wrapping.
    function add(U512 memory a, U512 memory b) internal pure returns (U512 memory) {
        uint256 lo;
        uint256 carry;
        unchecked {
            lo = a.lo + b.lo;
            carry = lo < a.lo ? 1 : 0;
        }
        return U512(a.hi + b.hi + carry, lo);
    }

    function cmp(U512 memory a, U512 memory b) internal pure returns (int256) {
        if (a.hi != b.hi) {
            return a.hi < b.hi ? int256(-1) : int256(1);
        }
        if (a.lo != b.lo) {
            return a.lo < b.lo ? int256(-1) : int256(1);
        }
        return 0;
    }

    function isZero(U512 memory x) internal pure returns (bool) {
        return x.hi == 0 && x.lo == 0;
    }

    /// The number of decimal digits of a non-zero `x` below 10^154.
    function digits(U512 memory x) internal pure returns (int256 n) {
        U512 memory p = u512(1);
        while (cmp(p, x) <= 0) {
            p = mulSmall(p, 10);
            n++;
        }
    }

    /// Compares `x × 10^ex` with `y × 10^ey`, returning -1, 0 or 1.
    /// Magnitudes must be below 10^154.
    function cmpScaled(U512 memory x, int256 ex, U512 memory y, int256 ey) internal pure returns (int256) {
        if (isZero(x) || isZero(y)) {
            return cmp(x, y);
        }
        int256 dx = digits(x);
        int256 dy = digits(y);
        // The position of each leading digit decides unless they coincide.
        if (dx + ex != dy + ey) {
            return dx + ex < dy + ey ? int256(-1) : int256(1);
        }
        // Equal leading positions: align the one with fewer digits up to the
        // other's digit count, which is below 10^154 by precondition.
        if (ex > ey) {
            // forge-lint: disable-next-line(unsafe-typecast)
            x = mulPow10(x, uint256(ex - ey));
        } else if (ey > ex) {
            // forge-lint: disable-next-line(unsafe-typecast)
            y = mulPow10(y, uint256(ey - ex));
        }
        return cmp(x, y);
    }

    function abs(int256 x) internal pure returns (uint256) {
        // -(x + 1) cannot overflow for negative x, including int256.min.
        // forge-lint: disable-next-line(unsafe-typecast)
        return x < 0 ? uint256(-(x + 1)) + 1 : uint256(x);
    }

    /// Whether the exact non-zero `magnitude × 10^exponent`, of either sign,
    /// packs past every Float.
    /// Exponents far enough from int32.max decide alone, as the magnitude has
    /// at most 155 digits, which also keeps `cmpScaled` clear of int256
    /// overflow for any exponent.
    function overflows(U512 memory magnitude, int256 exponent) internal pure returns (bool) {
        if (isZero(magnitude)) {
            return false;
        }
        if (exponent > int256(type(int32).max) + 200) {
            return true;
        }
        if (exponent < int256(type(int32).max) - 400) {
            return false;
        }
        return cmpScaled(magnitude, exponent, u512(OVERFLOW_FLOOR), type(int32).max) >= 0;
    }

    /// Whether the exact non-zero `magnitude × 10^exponent` is below the
    /// smallest positive Float. Exponents far from int32.min decide alone, as
    /// for `overflows`.
    function underflows(U512 memory magnitude, int256 exponent) internal pure returns (bool) {
        if (isZero(magnitude) || exponent >= type(int32).min) {
            return false;
        }
        if (exponent < int256(type(int32).min) - 200) {
            return true;
        }
        return cmpScaled(magnitude, exponent, u512(1), type(int32).min) < 0;
    }

    /// `|a × b|` overflows, given Float operands.
    function mulOverflows(int256 ca, int256 ea, int256 cb, int256 eb) internal pure returns (bool) {
        if (ca == 0 || cb == 0) {
            return false;
        }
        return overflows(mul(abs(ca), abs(cb)), ea + eb);
    }

    /// `|a × b|` underflows, given Float operands.
    function mulUnderflows(int256 ca, int256 ea, int256 cb, int256 eb) internal pure returns (bool) {
        return underflows(mul(abs(ca), abs(cb)), ea + eb);
    }

    /// `|a / b|` overflows, given Float operands and a non-zero `b`.
    /// `|ca| × 10^(ea-eb) >= floor × |cb| × 10^int32.max`.
    function divOverflows(int256 ca, int256 ea, int256 cb, int256 eb) internal pure returns (bool) {
        if (ca == 0) {
            return false;
        }
        return cmpScaled(u512(abs(ca)), ea - eb, mul(OVERFLOW_FLOOR, abs(cb)), type(int32).max) >= 0;
    }

    /// `|a / b|` underflows, given Float operands and a non-zero `b`.
    /// `|ca| × 10^(ea-eb) < |cb| × 10^int32.min`.
    function divUnderflows(int256 ca, int256 ea, int256 cb, int256 eb) internal pure returns (bool) {
        if (ca == 0) {
            return false;
        }
        return cmpScaled(u512(abs(ca)), ea - eb, u512(abs(cb)), type(int32).min) < 0;
    }

    /// `a + b` overflows, given Float operands. Only a same signed sum can
    /// exceed both operands in magnitude, and only it can overflow.
    function addOverflows(int256 ca, int256 ea, int256 cb, int256 eb) internal pure returns (bool) {
        if (ca == 0 || cb == 0 || (ca < 0) != (cb < 0)) {
            return false;
        }
        if (ea < eb) {
            (ca, ea, cb, eb) = (cb, eb, ca, ea);
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 gap = uint256(ea - eb);
        if (gap <= 67) {
            // Exact: |ca| × 10^gap + |cb| at eb, below 2^223 × 10^68.
            U512 memory sum = add(mulPow10(u512(abs(ca)), gap), u512(abs(cb)));
            return overflows(sum, eb);
        }
        // |cb| < 10^68 <= 10^gap, so b is below one unit of a's exponent. Below
        // a's exponent no multiple of 10^int32.max lies between a and a + b.
        // At or above it, a is such a multiple and b adds its own floor.
        int256 m = type(int32).max;
        if (ea <= m) {
            return overflows(u512(abs(ca)), ea);
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 lift = uint256(ea - m);
        if (lift >= 68) {
            return true;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 drop = uint256(m - eb);
        uint256 bFloor = drop > 77 ? 0 : abs(cb) / 10 ** drop;
        U512 memory floorAtMax = add(mulPow10(u512(abs(ca)), lift), u512(bFloor));
        return cmp(floorAtMax, u512(OVERFLOW_FLOOR)) >= 0;
    }

    /// The exact `coefficient × 10^(exponent + decimals)` as a fixed point
    /// uint256 from int224/int32 parts: a negative value is an error, a value
    /// at or above 2^256 is an error, and anything else is that value
    /// truncated, lossless iff nothing was truncated.
    function toFixedDecimal(int256 signedCoefficient, int256 exponent, uint8 decimals)
        internal
        pure
        returns (bytes memory err, uint256 value, bool lossless)
    {
        if (signedCoefficient < 0) {
            err = abi.encodeWithSelector(NegativeFixedDecimalConversion.selector, signedCoefficient, exponent);
            return (err, value, lossless);
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 coefficient = uint256(signedCoefficient);
        int256 finalExponent = exponent + int256(uint256(decimals));
        if (finalExponent >= 0) {
            // 10^78 alone exceeds 2^256.
            bool tooLarge = coefficient != 0 && finalExponent > 77;
            if (!tooLarge && coefficient != 0) {
                uint256 high;
                // forge-lint: disable-next-line(unsafe-typecast)
                (high, value) = Math.mul512(coefficient, 10 ** uint256(finalExponent));
                tooLarge = high != 0;
            }
            if (tooLarge) {
                err = abi.encodeWithSelector(FixedDecimalOverflow.selector, signedCoefficient, exponent, decimals);
                value = 0;
            }
            lossless = !tooLarge;
        } else if (finalExponent >= -77) {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 scale = 10 ** uint256(-finalExponent);
            value = coefficient / scale;
            lossless = coefficient % scale == 0;
        } else {
            // 10^78 alone exceeds any int224 coefficient.
            lossless = coefficient == 0;
        }
    }

    /// `signedCoefficient × 10^exponent` with the largest coefficient magnitude
    /// int256 holds: it multiplies by ten until the next multiply would
    /// overflow, then lowers the exponent by that shift, stopping at
    /// `type(int256).min` and returning what is left as the shortfall. Zero is
    /// `(0, 0, 0)`.
    function maximize(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256, int256) {
        if (signedCoefficient == 0) {
            return (0, 0, 0);
        }
        int256 shift = 0;
        while (true) {
            int256 next;
            unchecked {
                next = signedCoefficient * 10;
            }
            if (next / 10 != signedCoefficient) {
                break;
            }
            signedCoefficient = next;
            ++shift;
        }
        if (exponent < type(int256).min + shift) {
            return (signedCoefficient, type(int256).min, shift - (exponent - type(int256).min));
        }
        return (signedCoefficient, exponent - shift, 0);
    }

    /// `maximize` of a Float's parts, which never reaches the int256 floor.
    function maximizeFloat(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        (int256 maximized, int256 maximizedExponent, int256 shortfall) = maximize(signedCoefficient, exponent);
        require(shortfall == 0, "Float maximize shortfall");
        return (maximized, maximizedExponent);
    }

    /// A non-negative magnitude and a sign as int256 parts. A magnitude past
    /// int256 sheds one digit and raises the exponent, except `2^255` negative,
    /// which is `type(int256).min` exactly.
    function signedParts(bool negative, uint256 magnitude, int256 exponent) internal pure returns (int256, int256) {
        if (negative && magnitude == uint256(type(int256).max) + 1) {
            return (type(int256).min, exponent);
        }
        if (magnitude > uint256(type(int256).max)) {
            magnitude /= 10;
            exponent += 1;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedMagnitude = int256(magnitude);
        return (negative ? -signedMagnitude : signedMagnitude, exponent);
    }

    /// The parts `mul` of two Floats hands to packing, which are what its
    /// `ExponentOverflow` and `ExponentUnderflow` carry: the exact product
    /// floored to the fewest digits shed that fit 256 bits, as `signedParts`.
    /// The 512 bit product is below `10^k × 2^256` iff its high word is below
    /// `10^k`.
    function mulParts(int256 ca, int256 ea, int256 cb, int256 eb) internal pure returns (int256, int256) {
        if (ca == 0 || cb == 0) {
            return (0, 0);
        }
        U512 memory product = mul(abs(ca), abs(cb));
        uint256 shed = 0;
        while (product.hi >= 10 ** shed) {
            shed++;
        }
        uint256 magnitude = Math.mulDiv(abs(ca), abs(cb), 10 ** shed);
        // The product is at most 2^510, so its high word is at most 2^254 and
        // shed is at most 77.
        // forge-lint: disable-next-line(unsafe-typecast)
        return signedParts((ca < 0) != (cb < 0), magnitude, ea + eb + int256(shed));
    }

    /// The parts `div` of two Floats hands to packing, for a non-zero `cb`:
    /// both operands maximized, the dividend's magnitude scaled by the largest
    /// power of ten not above the divisor's and floor divided by it, as
    /// `signedParts`.
    function divParts(int256 ca, int256 ea, int256 cb, int256 eb) internal pure returns (int256, int256) {
        if (ca == 0) {
            return (0, 0);
        }
        (int256 maximizedA, int256 exponentA) = maximizeFloat(ca, ea);
        (int256 maximizedB, int256 exponentB) = maximizeFloat(cb, eb);
        uint256 magnitudeB = abs(maximizedB);
        uint256 scaleDigits = 0;
        while (10 ** (scaleDigits + 1) <= magnitudeB) {
            scaleDigits++;
        }
        uint256 magnitude = Math.mulDiv(abs(maximizedA), 10 ** scaleDigits, magnitudeB);
        // scaleDigits is at most 76.
        // forge-lint: disable-next-line(unsafe-typecast)
        return signedParts((ca < 0) != (cb < 0), magnitude, exponentA - int256(scaleDigits) - exponentB);
    }

    /// The parts `inv` of a non-zero Float hands to packing: `1e76 × 10^-76`
    /// divided by it.
    function invParts(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        return divParts(1e76, -76, signedCoefficient, exponent);
    }

    /// The exponent of a non-zero Float's int256 unit: its last digit when
    /// written with as many digits as an int256 coefficient holds, 77 or 76.
    function int256Unit(int256 signedCoefficient, int256 exponent) internal pure returns (int256) {
        uint256 magnitude = abs(signedCoefficient);
        int256 n = digits(u512(magnitude));
        // n is at most 68, and a 77 digit magnitude fits uint256.
        // forge-lint: disable-next-line(unsafe-typecast)
        bool fits77 = magnitude * 10 ** uint256(77 - n) <= uint256(type(int256).max);
        return exponent + n - (fits77 ? int256(77) : int256(76));
    }

    /// The parts `add` of two Floats hands to packing, as its NatSpec states
    /// them: the exact sum in units of the larger operand's int256 unit,
    /// rounded towards zero when the signs agree and away from zero when they
    /// differ, as `signedParts`. The larger operand is a whole number of
    /// units; the smaller is split into whole units and whether a fraction of
    /// one remains.
    function addParts(int256 ca, int256 ea, int256 cb, int256 eb) internal pure returns (int256, int256) {
        if (ca == 0) {
            return (cb, eb);
        }
        if (cb == 0) {
            return (ca, ea);
        }
        if (cmpScaled(u512(abs(ca)), ea, u512(abs(cb)), eb) < 0) {
            (ca, ea, cb, eb) = (cb, eb, ca, ea);
        }
        int256 unit = int256Unit(ca, ea);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 bigUnits = abs(ca) * 10 ** uint256(ea - unit);
        uint256 smallUnits;
        bool smallFraction;
        if (eb >= unit) {
            // |cb| × 10^(eb - unit) is at most |a|'s 77 digits.
            // forge-lint: disable-next-line(unsafe-typecast)
            smallUnits = abs(cb) * 10 ** uint256(eb - unit);
        } else if (unit - eb > 68) {
            // |cb| has at most 68 digits, so it is under one unit.
            smallFraction = true;
        } else {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 scale = 10 ** uint256(unit - eb);
            smallUnits = abs(cb) / scale;
            smallFraction = abs(cb) % scale != 0;
        }
        bool sameSign = (ca < 0) == (cb < 0);
        uint256 units;
        if (sameSign) {
            // Towards zero drops the fraction.
            units = bigUnits + smallUnits;
        } else {
            // |b| <= |a|, so this is at least zero: the whole units of the
            // exact difference, then away from zero rounds a remaining
            // fraction up to a unit.
            units = bigUnits - smallUnits - (smallFraction ? 1 : 0);
            if (smallFraction) {
                units += 1;
            }
        }
        return signedParts(ca < 0, units, unit);
    }

    /// `signedCoefficient × 10^(type(int256).min + headroom)` held at the
    /// int256 exponent floor: a negative headroom truncates that many digits
    /// towards zero, and a coefficient that truncates to zero is `(0, 0)`.
    function atFloor(int256 signedCoefficient, int256 headroom) internal pure returns (int256, int256) {
        if (headroom < 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            signedCoefficient = headroom < -76 ? int256(0) : signedCoefficient / int256(10 ** uint256(-headroom));
            headroom = 0;
        }
        if (signedCoefficient == 0) {
            return (0, 0);
        }
        return (signedCoefficient, type(int256).min + headroom);
    }

    /// Whether a Float's parts are a whole number. Below `10^-67` every
    /// non-zero int224 coefficient leaves a fraction.
    function isWhole(int256 signedCoefficient, int256 exponent) internal pure returns (bool) {
        if (exponent >= 0 || signedCoefficient == 0) {
            return true;
        }
        if (exponent < -67) {
            return false;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return signedCoefficient % int256(10 ** uint256(-exponent)) == 0;
    }

    /// Exact numeric equality of two Floats' parts.
    function eq(int256 ca, int256 ea, int256 cb, int256 eb) internal pure returns (bool) {
        if (ca == 0 || cb == 0) {
            return ca == cb;
        }
        if ((ca < 0) != (cb < 0)) {
            return false;
        }
        return cmpScaled(u512(abs(ca)), ea, u512(abs(cb)), eb) == 0;
    }
}
