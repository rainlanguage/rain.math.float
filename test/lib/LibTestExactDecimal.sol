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
    /// A positive result packs iff its floor at `10^int32.max` fits int224, so
    /// it overflows from `2^223 × 10^int32.max` up.
    uint256 internal constant POSITIVE_OVERFLOW_FLOOR = 2 ** 223;
    /// A negative result is truncated towards zero and `-2^223` fits int224, so
    /// it overflows from `(2^223 + 1) × 10^int32.max` up.
    uint256 internal constant NEGATIVE_OVERFLOW_FLOOR = 2 ** 223 + 1;

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

    function overflowFloor(bool negative) internal pure returns (uint256) {
        return negative ? NEGATIVE_OVERFLOW_FLOOR : POSITIVE_OVERFLOW_FLOOR;
    }

    /// Whether the exact non-zero `magnitude × 10^exponent`, with the given
    /// sign, is beyond the largest Float of that sign once truncated towards
    /// zero.
    /// Exponents far enough from int32.max decide alone, as the magnitude has
    /// at most 155 digits, which also keeps `cmpScaled` clear of int256
    /// overflow for any exponent.
    function overflows(U512 memory magnitude, int256 exponent, bool negative) internal pure returns (bool) {
        if (isZero(magnitude)) {
            return false;
        }
        if (exponent > int256(type(int32).max) + 200) {
            return true;
        }
        if (exponent < int256(type(int32).max) - 400) {
            return false;
        }
        return cmpScaled(magnitude, exponent, u512(overflowFloor(negative)), type(int32).max) >= 0;
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
        return overflows(mul(abs(ca), abs(cb)), ea + eb, (ca < 0) != (cb < 0));
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
        return
            cmpScaled(u512(abs(ca)), ea - eb, mul(overflowFloor((ca < 0) != (cb < 0)), abs(cb)), type(int32).max) >= 0;
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
        bool negative = ca < 0;
        if (ea < eb) {
            (ca, ea, cb, eb) = (cb, eb, ca, ea);
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 gap = uint256(ea - eb);
        if (gap <= 67) {
            // Exact: |ca| × 10^gap + |cb| at eb, below 2^223 × 10^68.
            U512 memory sum = add(mulPow10(u512(abs(ca)), gap), u512(abs(cb)));
            return overflows(sum, eb, negative);
        }
        // |cb| < 10^68 <= 10^gap, so b is below one unit of a's exponent. Below
        // a's exponent no multiple of 10^int32.max lies between a and a + b.
        // At or above it, a is such a multiple and b adds its own floor.
        int256 m = type(int32).max;
        if (ea <= m) {
            return overflows(u512(abs(ca)), ea, negative);
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
        return cmp(floorAtMax, u512(overflowFloor(negative))) >= 0;
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
