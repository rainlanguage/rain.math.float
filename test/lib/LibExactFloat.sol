// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";
import {NegativeFixedDecimalConversion, FixedDecimalOverflow} from "src/error/ErrDecimalFloat.sol";

/// @dev Fixed point one for the oracle, twenty digits past the library's 1e50.
uint256 constant ORACLE_ONE = 1e70;

/// @dev ln(10) at `ORACLE_ONE`, truncated, from `bc -l` at scale 100.
uint256 constant ORACLE_LN10 = 23025850929940456840179914546843642076011014886287729760333279009675726;

/// @dev ln(2) at `ORACLE_ONE`, truncated, from `bc -l` at scale 120.
uint256 constant ORACLE_LN2 = 6931471805599453094172321214581765680755001343602552541206800094933936;

/// An unsigned integer below 2^512.
struct U512 {
    uint256 hi;
    uint256 lo;
}

/// A sum operand: `±magnitude × 10^exponent`, and `unitShift`, as
/// `LibExactFloat.int256UnitShift` gives it for the coefficient's int256 unit.
struct Operand {
    bool negative;
    uint256 magnitude;
    int256 exponent;
    int256 unitShift;
}

/// Exact decimal comparisons, independent of the library under test. Values
/// are `magnitude × 10^exponent` with a 512 bit magnitude, and every
/// comparison is decided in exact integer arithmetic. The `*Payload` functions
/// state the unpacked parts the implementation hands to packing by its own
/// steps: they pin that representation and the revert payloads that carry
/// it, never a packed value, which `isNearestTowardZero` checks.
library LibExactFloat {
    /// A result packs iff the magnitude of its floor at `10^int32.max` is at
    /// most `2^223 + 1`: that far past the int224 bound of its sign, shedding a
    /// digit would land below the bound, so it takes the bound (#332). Either
    /// sign overflows from `(2^223 + 2) × 10^int32.max` up in magnitude.
    uint256 internal constant OVERFLOW_FLOOR = 2 ** 223 + 2;

    function u512(uint256 x) internal pure returns (U512 memory) {
        return U512(0, x);
    }

    /// The 512 bit product by schoolbook multiplication of 128 bit limbs,
    /// independent of the CRT trick `mul512` uses.
    function mul(uint256 a, uint256 b) internal pure returns (U512 memory) {
        (uint256 hi, uint256 lo) = mulWords(a, b);
        return U512(hi, lo);
    }

    /// `mul` as its two words, without allocating.
    function mulWords(uint256 a, uint256 b) internal pure returns (uint256 hi, uint256 lo) {
        // Limb products are below 2^256 and the full product below 2^512, so
        // no step wraps.
        unchecked {
            uint256 mask = type(uint128).max;
            uint256 lowLow = (a & mask) * (b & mask);
            uint256 lowHigh = (a & mask) * (b >> 128);
            uint256 highLow = (a >> 128) * (b & mask);
            uint256 highHigh = (a >> 128) * (b >> 128);
            uint256 middle = (lowLow >> 128) + (lowHigh & mask) + (highLow & mask);
            hi = highHigh + (lowHigh >> 128) + (highLow >> 128) + (middle >> 128);
            lo = (lowLow & mask) | ((middle & mask) << 128);
        }
    }

    function words(U512 memory x) internal pure returns (uint256, uint256) {
        return (x.hi, x.lo);
    }

    /// Checked: a product at or above 2^512 panics rather than wrapping.
    function mulSmall(U512 memory x, uint256 m) internal pure returns (U512 memory) {
        (uint256 carry, uint256 lo) = mulWords(x.lo, m);
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
        if (x.hi == 0) {
            for (uint256 rest = x.lo; rest > 0; rest /= 10) {
                n++;
            }
            return n;
        }
        uint256 pHi = 0;
        uint256 pLo = 1;
        while (pHi < x.hi || (pHi == x.hi && pLo <= x.lo)) {
            (uint256 carry, uint256 lo) = mulWords(pLo, 10);
            (pHi, pLo) = (pHi * 10 + carry, lo);
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
    /// uint256 from int256 parts: a negative value is an error, a value at or
    /// above 2^256 is an error, and anything else is that value truncated,
    /// lossless iff nothing was truncated.
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
        // Past 77 the value is past 2^256 whatever the decimals, so 78 stands
        // for any such sum without overflowing int256.
        int256 finalExponent = exponent > 77 ? int256(78) : exponent + int256(uint256(decimals));
        if (finalExponent >= 0) {
            // 10^78 alone exceeds 2^256.
            bool tooLarge = coefficient != 0 && finalExponent > 77;
            if (!tooLarge && coefficient != 0) {
                uint256 high;
                // forge-lint: disable-next-line(unsafe-typecast)
                (high, value) = mulWords(coefficient, 10 ** uint256(finalExponent));
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
            // 10^78 alone exceeds any int256 coefficient.
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
    /// `ExponentOverflow` and `ExponentUnderflow` carry: `productInt256` at the
    /// exponent sum, and `(0, 0)` for a zero operand.
    function mulPayload(int256 ca, int256 ea, int256 cb, int256 eb) internal pure returns (int256, int256) {
        if (ca == 0 || cb == 0) {
            return (0, 0);
        }
        (int256 product, int256 dropped) = productInt256(ca, cb);
        return (product, ea + eb + dropped);
    }

    /// `|ca| / |cb|` in units of `10^-offset`, truncated: the dividend
    /// lifted to its int256 unit over the divisor's leading digit, so `offset`
    /// is `int256UnitShift(ca) + digits(cb) - 1`. At most `2^255`.
    function quotientAtUnit(int256 ca, int256 cb) internal pure returns (uint256 magnitude, int256 offset) {
        int256 lift = int256UnitShift(ca);
        int256 leadB = digits(u512(abs(cb))) - 1;
        // forge-lint: disable-next-line(unsafe-typecast)
        magnitude = Math.mulDiv(abs(ca) * 10 ** uint256(lift), 10 ** uint256(leadB), abs(cb));
        offset = lift + leadB;
    }

    /// The parts `div` of two Floats returns, for a non-zero `cb`, as its
    /// NatSpec states them: `a / b` truncated toward zero at `10^(ua - lb)`,
    /// `ua` the dividend's int256 unit and `lb` the divisor's leading digit's
    /// exponent, as `signedParts`.
    function divParts(int256 ca, int256 ea, int256 cb, int256 eb) internal pure returns (int256 c, int256 e) {
        bool overflowed;
        (overflowed, c, e) = divPartsWide(ca, ea, cb, eb);
        require(!overflowed, "divParts overflowed");
    }

    /// The parts `inv` of a non-zero Float returns: `1e76 × 10^-76` over it.
    function invParts(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        return divParts(1e76, -76, signedCoefficient, exponent);
    }

    /// `divParts` for any int256 parts and a non-zero `cb`, or `overflowed`
    /// where `ua - lb` is above `type(int256).max`. A positive 2^255 sheds its
    /// last digit, which overflows at `type(int256).max`. Below
    /// `type(int256).min` the exact quotient truncates toward zero at it, and
    /// zero is `(0, 0)`.
    function divPartsWide(int256 ca, int256 ea, int256 cb, int256 eb)
        internal
        pure
        returns (bool overflowed, int256 c, int256 e)
    {
        if (ca == 0) {
            // forge-lint: disable-next-line(boolean-cst)
            return (false, 0, 0);
        }
        bool negative = (ca < 0) != (cb < 0);
        (uint256 magnitude, int256 offset) = quotientAtUnit(ca, cb);
        int256 cls;
        (cls, e) = wideExponent(ea, eb, 0, -offset);
        if (cls == 1 || (cls == 0 && !negative && magnitude > uint256(type(int256).max) && e == type(int256).max)) {
            // forge-lint: disable-next-line(boolean-cst)
            return (true, 0, 0);
        }
        if (cls == -1) {
            // The unit is `e` digits below the floor: shed them from the
            // truncated quotient, which truncates the exact one there.
            magnitude = shed(magnitude, e);
            e = magnitude == 0 ? int256(0) : type(int256).min;
        }
        (c, e) = signedParts(negative, magnitude, e);
    }

    /// Whether `(c, e)` is `a / b` truncated toward zero at `10^e`, decided in
    /// exact integer arithmetic for any int256 parts and a non-zero `cb`.
    /// Zero is `(0, 0)`, only for a quotient below `10^type(int256).min`.
    function isTruncatedQuotient(int256 ca, int256 ea, int256 cb, int256 eb, int256 c, int256 e)
        internal
        pure
        returns (bool)
    {
        if (ca == 0) {
            return c == 0 && e == 0;
        }
        if (c != 0 && (c < 0) != ((ca < 0) != (cb < 0))) {
            return false;
        }
        U512 memory a = u512(abs(ca));
        uint256 b = abs(cb);
        if (c == 0) {
            // |a| 10^ea < |b| 10^(eb + int256.min).
            return e == 0 && cmpWide(u512(b), eb, ea, type(int256).min, 0, a) > 0;
        }
        // |c| |b| 10^(e + eb) <= |a| 10^ea < (|c| + 1) |b| 10^(e + eb).
        return cmpWide(mul(abs(c), b), e, ea, eb, 0, a) <= 0 && cmpWide(mul(abs(c) + 1, b), e, ea, eb, 0, a) > 0;
    }

    /// `mulPayload` at any int256 exponents: `overflowed` where the exponent is
    /// above `type(int256).max`, and below `10^type(int256).min` the digits
    /// truncated towards zero as `atFloor`. Zero is `(0, 0)`.
    function mulPayloadWide(int256 ca, int256 ea, int256 cb, int256 eb) internal pure returns (bool, int256, int256) {
        (int256 c, int256 k) = mulPayload(ca, 0, cb, 0);
        if (c == 0) {
            // forge-lint: disable-next-line(boolean-cst)
            return (false, 0, 0);
        }
        (int256 cls, int256 e) = wideExponent(ea, 0, eb, k);
        if (cls == 1) {
            // forge-lint: disable-next-line(boolean-cst)
            return (true, 0, 0);
        }
        if (cls == -1) {
            (c, e) = atFloor(c, -e);
        }
        // forge-lint: disable-next-line(boolean-cst)
        return (false, c, e);
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

    /// `p - q + r + k` against the int256 range, for `|k|` below 1000. `cls` is
    /// 1 above it, -1 below it with `value` the distance under
    /// `type(int256).min`, saturated at 10^6, and otherwise 0 with `value` the
    /// sum. Quarters of int256 sum without overflow.
    function wideExponent(int256 p, int256 q, int256 r, int256 k) internal pure returns (int256 cls, int256 value) {
        int256 h = (p >> 2) - (q >> 2) + (r >> 2);
        int256 l = (p & 3) - (q & 3) + (r & 3) + k;
        int256 dMax = h - (type(int256).max >> 2);
        if (dMax > 1000) {
            return (1, 0);
        }
        if (dMax >= -1000) {
            int256 t = 4 * dMax + l - 3;
            return t > 0 ? (int256(1), int256(0)) : (int256(0), type(int256).max + t);
        }
        int256 dMin = h - (type(int256).min >> 2);
        if (dMin < -1000) {
            return (-1, 1e6);
        }
        if (dMin <= 1000) {
            int256 t = 4 * dMin + l;
            return t < 0 ? (int256(-1), -t) : (int256(0), type(int256).min + t);
        }
        return (0, 4 * h + l);
    }

    /// Compares `x × 10^(p - q + r + k)` with `y`, for `|k|` below 1000.
    function cmpWide(U512 memory x, int256 p, int256 q, int256 r, int256 k, U512 memory y)
        internal
        pure
        returns (int256)
    {
        if (isZero(x) || isZero(y)) {
            return cmp(x, y);
        }
        (int256 cls, int256 d) = wideExponent(p, q, r, k);
        // Both magnitudes are below 10^155, so a shift past 400 decides.
        if (cls == 1 || (cls == 0 && d > 400)) {
            return 1;
        }
        if (cls == -1 || d < -400) {
            return -1;
        }
        return cmpScaled(x, d, y, 0);
    }

    /// The truncated magnitude of `|c| / 10^u`, zero from `u = 78`.
    function shed(uint256 magnitude, int256 u) internal pure returns (uint256) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return u >= 78 ? 0 : magnitude / 10 ** uint256(u);
    }

    /// How many digits a non-zero coefficient shifts left to its int256 unit:
    /// as many digits as an int256 coefficient of its sign holds, 77 or 76,
    /// less its own.
    function int256UnitShift(int256 signedCoefficient) internal pure returns (int256) {
        uint256 magnitude = abs(signedCoefficient);
        uint256 limit = signedCoefficient < 0 ? uint256(type(int256).max) + 1 : uint256(type(int256).max);
        int256 n = digits(u512(magnitude));
        // n is at most 77, and a 77 digit magnitude fits uint256.
        // forge-lint: disable-next-line(unsafe-typecast)
        return magnitude * 10 ** uint256(77 - n) <= limit ? 77 - n : 76 - n;
    }

    /// The exponent of a non-zero coefficient's int256 unit.
    function int256Unit(int256 signedCoefficient, int256 exponent) internal pure returns (int256) {
        return exponent - int256UnitShift(signedCoefficient);
    }

    /// The parts `add` of any two int256 coefficients hands to packing, or
    /// `overflowed` where its exponent is above `type(int256).max`, as its
    /// NatSpec states them: the exact sum truncated towards zero to a multiple
    /// of the larger operand's int256 unit, or of ten of them past int256.
    /// The int256 unit is the last digit's place when written with as many
    /// digits as an int256 coefficient of its sign holds, so
    /// `type(int256).min` holds 77. Below `type(int256).min` the sum then
    /// truncates towards zero to that exponent. A zero sum is `(0, 0)`.
    function addPartsWide(int256 ca, int256 ea, int256 cb, int256 eb)
        internal
        pure
        returns (bool overflowed, int256 c, int256 e)
    {
        (overflowed, c, e,) = addPartsInexact(ca, ea, cb, eb);
        e = c == 0 ? int256(0) : e;
    }

    /// `addPartsWide` with the magnitude rounded up instead, so never below
    /// the exact sum's, for a bound term that must not be underestimated.
    function addPartsWideUp(int256 ca, int256 ea, int256 cb, int256 eb)
        internal
        pure
        returns (bool overflowed, int256 c, int256 e)
    {
        bool inexact;
        (overflowed, c, e, inexact) = addPartsInexact(ca, ea, cb, eb);
        if (inexact && !overflowed) {
            // A truncated zero takes the sign of the larger operand.
            bool negative = c == 0 ? (cmpWide(u512(abs(ca)), ea, eb, 0, 0, u512(abs(cb))) < 0 ? cb < 0 : ca < 0) : c < 0;
            c += negative ? int256(-1) : int256(1);
        }
    }

    /// `addPartsWide`, and whether the truncation shed anything, so the exact
    /// sum is strictly between `c × 10^e` and one unit of `10^e` further from
    /// zero.
    function addPartsInexact(int256 ca, int256 ea, int256 cb, int256 eb)
        internal
        pure
        returns (bool overflowed, int256 c, int256 e, bool inexact)
    {
        return sumPartsInexact(operand(false, ca, ea), operand(false, cb, eb));
    }

    /// The parts `sub` of any two int256 coefficients hands to packing, or
    /// `overflowed` past `type(int256).max`: `addPartsWide`'s rule for the
    /// exact `a + (-b)`, where `-b` keeps `b`'s int256 unit, so the negation
    /// of `type(int256).min` is `2^255` at 77 digits. A zero difference is
    /// `(0, 0)`.
    function subPartsWide(int256 ca, int256 ea, int256 cb, int256 eb)
        internal
        pure
        returns (bool overflowed, int256 c, int256 e)
    {
        (overflowed, c, e,) = sumPartsInexact(operand(false, ca, ea), operand(true, cb, eb));
        e = c == 0 ? int256(0) : e;
    }

    /// `signedCoefficient × 10^exponent`, negated if `negate`, at the int256
    /// unit of `signedCoefficient`.
    function operand(bool negate, int256 signedCoefficient, int256 exponent) internal pure returns (Operand memory) {
        return Operand(
            negate ? signedCoefficient > 0 : signedCoefficient < 0,
            abs(signedCoefficient),
            exponent,
            signedCoefficient == 0 ? int256(0) : int256UnitShift(signedCoefficient)
        );
    }

    /// `addPartsInexact` of two operands.
    function sumPartsInexact(Operand memory a, Operand memory b)
        internal
        pure
        returns (bool overflowed, int256 c, int256 e, bool inexact)
    {
        if (a.magnitude == 0) {
            (a, b) = (b, a);
        }
        if (b.magnitude == 0) {
            // Only 2^255 positive is past int256 alone. It sheds a digit, past
            // every exponent from `type(int256).max`.
            inexact = !a.negative && a.magnitude > uint256(type(int256).max);
            if (inexact && a.exponent == type(int256).max) {
                // forge-lint: disable-next-line(boolean-cst)
                return (true, 0, 0, true);
            }
            (c, e) = signedParts(a.negative, a.magnitude, a.exponent);
            // forge-lint: disable-next-line(boolean-cst)
            return (false, c, e, inexact);
        }
        if (cmpWide(u512(a.magnitude), a.exponent, b.exponent, 0, 0, u512(b.magnitude)) < 0) {
            (a, b) = (b, a);
        }
        uint256 magnitude;
        int256 offset;
        (magnitude, offset, inexact) = addUnits(a, b);
        int256 cls;
        (cls, e) = wideExponent(a.exponent, 0, 0, offset);
        if (cls == 1) {
            // forge-lint: disable-next-line(boolean-cst)
            return (true, 0, 0, inexact);
        }
        if (cls == -1) {
            // forge-lint: disable-next-line(unsafe-typecast)
            inexact = inexact || (e >= 78 ? magnitude != 0 : magnitude % 10 ** uint256(e) != 0);
            magnitude = shed(magnitude, e);
            e = type(int256).min;
        }
        (c, e) = signedParts(a.negative, magnitude, e);
    }

    /// `addPartsWide`'s magnitude in units of `10^(a.exponent + offset)`, for
    /// non-zero operands with `|a| >= |b|`, and whether it is inexact.
    function addUnits(Operand memory a, Operand memory b)
        internal
        pure
        returns (uint256 magnitude, int256 offset, bool inexact)
    {
        uint256 limit = a.negative ? uint256(type(int256).max) + 1 : uint256(type(int256).max);
        // forge-lint: disable-next-line(unsafe-typecast)
        U512 memory units = u512(a.magnitude * 10 ** uint256(a.unitShift));
        U512 memory smallUnits;
        // Whether b has digits below the unit: all of them unless aligned.
        inexact = true;
        // eb - unit, where unit is ea - unitShift.
        (int256 cls, int256 gap) = wideExponent(b.exponent, a.exponent, 0, a.unitShift);
        if (cls == 0 && gap >= 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            smallUnits = mulPow10(u512(b.magnitude), uint256(gap));
            inexact = false;
        } else if (cls == 0 && gap > -78) {
            // forge-lint: disable-next-line(unsafe-typecast)
            smallUnits = u512(b.magnitude / 10 ** uint256(-gap));
            // forge-lint: disable-next-line(unsafe-typecast)
            inexact = b.magnitude % 10 ** uint256(-gap) != 0;
        }
        if (a.negative == b.negative) {
            // floor(|a| + |b|) = |a| + floor(|b|) for a whole |a|.
            units = add(units, smallUnits);
        } else {
            // |b| <= |a|. floor(|a| - |b|) = |a| - ceil(|b|) for a whole |a|,
            // and ceil(|b|) is floor(|b|) plus one where |b| is not whole.
            units = U512(0, units.lo - smallUnits.lo - (inexact ? 1 : 0));
        }
        offset = -a.unitShift;
        if (cmp(units, u512(limit)) > 0) {
            // units mod 10, as 2^256 is 6 mod 10.
            inexact = inexact || (units.hi * 6 + units.lo % 10) % 10 != 0;
            // At most 2^256, so 6 hi + lo does not overflow.
            return (units.hi * (type(uint256).max / 10) + (units.hi * 6 + units.lo) / 10, offset + 1, inexact);
        }
        return (units.lo, offset, inexact);
    }

    /// Exact numeric order of any two int256 coefficient and exponent pairs:
    /// -1, 0 or 1.
    function cmpParts(int256 ca, int256 ea, int256 cb, int256 eb) internal pure returns (int256) {
        int256 sa = ca < 0 ? int256(-1) : ca > 0 ? int256(1) : int256(0);
        int256 sb = cb < 0 ? int256(-1) : cb > 0 ? int256(1) : int256(0);
        if (sa != sb || sa == 0) {
            return sa < sb ? int256(-1) : sa > sb ? int256(1) : int256(0);
        }
        return sa * cmpWide(u512(abs(ca)), ea, eb, 0, 0, u512(abs(cb)));
    }

    /// `a / b` for a nonzero `b`, truncated towards zero once, so under 1e-74
    /// relative: `q = floor(|a| 10^k / |b|)` with `k = 75 + digits(b) -
    /// digits(a)` puts the exact ratio in (1e74, 1e76), so `q` is in
    /// [1e74, 1e76), 75 or 76 digits. That is more than any Float holds, so
    /// the closest Float not above the exact quotient is the closest not above
    /// `q × 10^e`.
    function quotient(int256 ca, int256 ea, int256 cb, int256 eb) internal pure returns (int256, int256) {
        if (ca == 0) {
            return (0, 0);
        }
        uint256 a = abs(ca);
        uint256 b = abs(cb);
        // Both at most 77 digits, so k is in [-1, 151].
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 k = 75 + int256(Math.log10(b)) - int256(Math.log10(a));
        uint256 q;
        if (k < 0) {
            // k = -1 only where b has one digit, so 10 b fits.
            q = a / (b * 10);
        } else if (k <= 77) {
            // forge-lint: disable-next-line(unsafe-typecast)
            q = Math.mulDiv(a, 10 ** uint256(k), b);
        } else {
            // a 10^(k - 77) is below 10^(digits(b) - 2).
            // forge-lint: disable-next-line(unsafe-typecast)
            q = Math.mulDiv(a * 10 ** uint256(k - 77), 1e77, b);
        }
        // q is below 1e76.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedQ = int256(q);
        return ((ca < 0) != (cb < 0) ? -signedQ : signedQ, ea - eb - k);
    }

    /// The coefficient of `c × 10^e` at exponent `target`, truncated towards
    /// zero, and reverting where it does not fit int256.
    function atExponent(int256 c, int256 e, int256 target) internal pure returns (int256) {
        if (e >= target) {
            // forge-lint: disable-next-line(unsafe-typecast)
            return c == 0 ? int256(0) : c * int256(10 ** uint256(e - target));
        }
        if (target - e > 76) {
            return 0;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return c / int256(10 ** uint256(target - e));
    }

    /// Exact numeric equality of two Floats' parts.
    function eq(int256 ca, int256 ea, int256 cb, int256 eb) internal pure returns (bool) {
        return cmpParts(ca, ea, cb, eb) == 0;
    }

    /// The largest coefficient magnitude a Float of the sign holds.
    function coefficientLimit(bool negative) internal pure returns (uint256) {
        return negative ? 2 ** 223 : 2 ** 223 - 1;
    }

    /// Whether the Float `(rc, re)` is what the general rule packs the exact
    /// `±magnitude × 10^exponent` to: zero for zero, otherwise the closest
    /// Float of the same sign that does not exceed it in magnitude. The caller
    /// rules out values that `overflows` or `underflows`, which no Float is.
    /// Magnitudes must be below 10^154.
    function isNearestTowardZero(bool negative, U512 memory magnitude, int256 exponent, int256 rc, int256 re)
        internal
        pure
        returns (bool)
    {
        if (isZero(magnitude)) {
            return rc == 0;
        }
        if (rc == 0 || (rc < 0) != negative) {
            return false;
        }
        if (cmpScaled(u512(abs(rc)), re, magnitude, exponent) > 0) {
            return false;
        }
        (bool none, uint256 next, int256 nextExponent) = nextFloat(negative, rc, re);
        return none || cmpScaled(magnitude, exponent, u512(next), nextExponent) < 0;
    }

    /// The magnitude of the Float of the sign one step further from zero than
    /// the non-zero `(rc, re)`, or `none` past the largest.
    function nextFloat(bool negative, int256 rc, int256 re)
        internal
        pure
        returns (bool none, uint256 next, int256 nextExponent)
    {
        uint256 r = abs(rc);
        uint256 limit = coefficientLimit(negative);
        // At its lowest exponent, the next larger Float is one unit up, or the
        // smallest past the limit one exponent higher.
        while (re > type(int32).min && r * 10 <= limit) {
            r *= 10;
            --re;
        }
        if (r < limit) {
            // forge-lint: disable-next-line(boolean-cst)
            return (false, r + 1, re);
        }
        if (re == type(int32).max) {
            // forge-lint: disable-next-line(boolean-cst)
            return (true, 0, 0);
        }
        // forge-lint: disable-next-line(boolean-cst)
        return (false, limit / 10 + 1, re + 1);
    }

    /// Whether the Float `(rc, re)` is what `add` documents for
    /// `ca × 10^ea + cb × 10^eb`: the exact sum rounded once towards zero, the
    /// closest Float not exceeding it in magnitude. `addPartsInexact` puts the
    /// exact sum at `c × 10^e`, or strictly between that and one unit of
    /// `10^e` further from zero. In the latter case the Float is the floor of
    /// the exact sum when it is that of `c × 10^e` and the next Float is at
    /// least a whole unit further. At most one Float is accepted. The caller
    /// rules out sums that `addOverflows`.
    function isSumResult(int256 ca, int256 ea, int256 cb, int256 eb, int256 rc, int256 re)
        internal
        pure
        returns (bool)
    {
        (, int256 c, int256 e, bool inexact) = addPartsInexact(ca, ea, cb, eb);
        if (!isNearestTowardZero(c < 0, u512(abs(c)), e, rc, re)) {
            return false;
        }
        if (!inexact) {
            return true;
        }
        if (rc == 0) {
            return false;
        }
        (bool none, uint256 next, int256 nextExponent) = nextFloat(c < 0, rc, re);
        return none || cmpScaled(u512(abs(c) + 1), e, u512(next), nextExponent) <= 0;
    }

    /// `a - b` for `a >= b`.
    function sub(U512 memory a, U512 memory b) internal pure returns (U512 memory) {
        require(cmp(a, b) >= 0, "negative difference");
        unchecked {
            return U512(a.hi - b.hi - (a.lo < b.lo ? 1 : 0), a.lo - b.lo);
        }
    }

    /// The exact `ca × 10^ea + cb × 10^eb` of two Floats' parts, as a sign, a
    /// magnitude below 10^150 and an exponent, independent of any int256
    /// unit. A Float with 68 digits at most puts the Floats beside the other
    /// operand at least 10^-70 of its leading place apart, and the other
    /// operand is one of them. So a non-zero operand whose leading digit is
    /// over 82 places below the other's moves the sum strictly between the
    /// same two Floats as any other value of its sign that far down: it
    /// becomes one unit 100 places below the other's leading digit.
    function exactSum(int256 ca, int256 ea, int256 cb, int256 eb)
        internal
        pure
        returns (bool negative, U512 memory magnitude, int256 exponent)
    {
        if (ca == 0 || cb == 0) {
            (int256 c, int256 e) = ca == 0 ? (cb, eb) : (ca, ea);
            return (c < 0, u512(abs(c)), e);
        }
        int256 ta = ea + digits(u512(abs(ca)));
        int256 tb = eb + digits(u512(abs(cb)));
        if (ta - tb > 82) {
            (cb, eb) = (cb < 0 ? int256(-1) : int256(1), ta - 100);
        } else if (tb - ta > 82) {
            (ca, ea) = (ca < 0 ? int256(-1) : int256(1), tb - 100);
        }
        exponent = ea < eb ? ea : eb;
        // forge-lint: disable-next-line(unsafe-typecast)
        U512 memory ma = mulPow10(u512(abs(ca)), uint256(ea - exponent));
        // forge-lint: disable-next-line(unsafe-typecast)
        U512 memory mb = mulPow10(u512(abs(cb)), uint256(eb - exponent));
        if ((ca < 0) == (cb < 0)) {
            return (ca < 0, add(ma, mb), exponent);
        }
        if (cmp(ma, mb) >= 0) {
            return (ca < 0, sub(ma, mb), exponent);
        }
        return (cb < 0, sub(mb, ma), exponent);
    }

    /// Whether `(rc, re)` is the exact sum of two Floats rounded once towards
    /// zero to a Float, from `exactSum` rather than `addPartsInexact`. The
    /// caller rules out sums that `addOverflows`.
    function isNearestSum(int256 ca, int256 ea, int256 cb, int256 eb, int256 rc, int256 re)
        internal
        pure
        returns (bool)
    {
        (bool negative, U512 memory magnitude, int256 exponent) = exactSum(ca, ea, cb, eb);
        return isNearestTowardZero(negative, magnitude, exponent, rc, re);
    }

    /// `ca × cb` with the fewest digits shed, truncating towards zero, that
    /// leave it in int256 of the product's sign, and the number shed.
    function productInt256(int256 ca, int256 cb) internal pure returns (int256, int256) {
        bool negative = (ca < 0) != (cb < 0);
        (uint256 productHi, uint256 productLo) = mulWords(abs(ca), abs(cb));
        // floor(product / 10^k) is within the bound iff product < (bound + 1) × 10^k.
        uint256 aboveBound = negative ? 2 ** 255 + 1 : 2 ** 255;
        uint256 dropped = 0;
        while (true) {
            (uint256 hi, uint256 lo) = mulWords(aboveBound, 10 ** dropped);
            if (productHi < hi || (productHi == hi && productLo < lo)) {
                break;
            }
            dropped++;
        }
        uint256 m = Math.mulDiv(abs(ca), abs(cb), 10 ** dropped);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signed = m == 2 ** 255 ? type(int256).min : (negative ? -int256(m) : int256(m));
        // forge-lint: disable-next-line(unsafe-typecast)
        return (signed, int256(dropped));
    }

    /// Whether `ca × 10^ea × cb × 10^eb` is exactly `cc × 10^ec`.
    function productEq(int256 ca, int256 ea, int256 cb, int256 eb, int256 cc, int256 ec) internal pure returns (bool) {
        if (ca == 0 || cb == 0 || cc == 0) {
            return (ca == 0 || cb == 0) && cc == 0;
        }
        if (((ca < 0) != (cb < 0)) != (cc < 0)) {
            return false;
        }
        return cmpScaled(mul(abs(ca), abs(cb)), ea + eb, u512(abs(cc)), ec) == 0;
    }

    /// Whether `|Σ cᵢ × 10^eᵢ| <= Σ bⱼ × 10^fⱼ` exactly, under `sums`.
    function absSumLte(
        int256[] memory coefficients,
        int256[] memory exponents,
        int256[] memory boundCoefficients,
        int256[] memory boundExponents
    ) internal pure returns (bool) {
        (U512 memory positive, U512 memory negative, U512 memory bound) =
            sums(coefficients, exponents, boundCoefficients, boundExponents);
        return cmp(positive, add(negative, bound)) <= 0 && cmp(negative, add(positive, bound)) <= 0;
    }

    /// Whether `Σ cᵢ × 10^eᵢ <= Σ bⱼ × 10^fⱼ` exactly, under `sums`.
    function sumLte(
        int256[] memory coefficients,
        int256[] memory exponents,
        int256[] memory boundCoefficients,
        int256[] memory boundExponents
    ) internal pure returns (bool) {
        (U512 memory positive, U512 memory negative, U512 memory bound) =
            sums(coefficients, exponents, boundCoefficients, boundExponents);
        return cmp(positive, add(negative, bound)) <= 0;
    }

    /// The positive and negative parts of `Σ cᵢ × 10^eᵢ`, and `Σ bⱼ × 10^fⱼ`
    /// for non-negative `bⱼ`. Every term is scaled to the least exponent of a
    /// non-zero term, so every magnitude scaled there must stay below 2^512.
    function sums(
        int256[] memory coefficients,
        int256[] memory exponents,
        int256[] memory boundCoefficients,
        int256[] memory boundExponents
    ) private pure returns (U512 memory positive, U512 memory negative, U512 memory bound) {
        int256 floor = type(int256).max;
        for (uint256 i = 0; i < coefficients.length; i++) {
            if (coefficients[i] != 0 && exponents[i] < floor) {
                floor = exponents[i];
            }
        }
        for (uint256 i = 0; i < boundCoefficients.length; i++) {
            require(boundCoefficients[i] >= 0, "negative bound");
            if (boundCoefficients[i] != 0 && boundExponents[i] < floor) {
                floor = boundExponents[i];
            }
        }
        positive = u512(0);
        negative = u512(0);
        bound = u512(0);
        for (uint256 i = 0; i < coefficients.length; i++) {
            if (coefficients[i] == 0) {
                continue;
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            U512 memory scaled = mulPow10(u512(abs(coefficients[i])), uint256(exponents[i] - floor));
            if (coefficients[i] < 0) {
                negative = add(negative, scaled);
            } else {
                positive = add(positive, scaled);
            }
        }
        for (uint256 i = 0; i < boundCoefficients.length; i++) {
            if (boundCoefficients[i] == 0) {
                continue;
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            bound = add(bound, mulPow10(u512(abs(boundCoefficients[i])), uint256(boundExponents[i] - floor)));
        }
    }

    /// The integer part of `c 10^e`, truncated toward zero, and the rest, both
    /// at `10^e`: `c` is their exact sum.
    function wholeAndFraction(int256 c, int256 e) internal pure returns (int256 whole, int256 fraction) {
        if (e >= 0) {
            return (c, 0);
        }
        if (e < -76) {
            return (0, c);
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 unit = int256(10 ** uint256(-e));
        fraction = c % unit;
        whole = c - fraction;
    }

    /// The greatest integer not above `c 10^e`, as parts. One unit of `10^-e`
    /// below an int224 coefficient fits int256; below `10^-76` the floor of a
    /// negative value is `-1`.
    function floorParts(int256 c, int256 e) internal pure returns (int256, int256) {
        (int256 whole, int256 fraction) = wholeAndFraction(c, e);
        if (fraction >= 0) {
            return (whole, e);
        }
        if (e < -76) {
            return (-1, 0);
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return (whole - int256(10 ** uint256(-e)), e);
    }

    /// The least integer not below `c 10^e`, as parts.
    function ceilParts(int256 c, int256 e) internal pure returns (int256, int256) {
        (int256 whole, int256 fraction) = wholeAndFraction(c, e);
        if (fraction <= 0) {
            return (whole, e);
        }
        if (e < -76) {
            return (1, 0);
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return (whole + int256(10 ** uint256(-e)), e);
    }

    // Transcendental reference values, independent of the library: plain
    // Taylor series over OpenZeppelin's mulDiv, against bc constants.
    /// log10 of the primes the tests raise, at `ORACLE_ONE`, truncated, from
    /// `bc -l` at scale 100.
    function log10Prime(uint256 prime) internal pure returns (uint256) {
        if (prime == 2) {
            return 3010299956639811952137388947244930267681898814621085413104274611271081;
        } else if (prime == 3) {
            return 4771212547196624372950279032551153092001288641906958648298656403052291;
        } else if (prime == 7) {
            return 8450980400142568307122162585926361934835723963239654065036349537182534;
        }
        revert("prime");
    }

    /// The largest j with prime^j below 1e30.
    function maxPower(uint256 prime) internal pure returns (uint256) {
        if (prime == 2) {
            return 99;
        } else if (prime == 3) {
            return 62;
        }
        return 35;
    }

    /// ln(1 + u) / u at `ORACLE_ONE` for u = d / 10^p, negated when `negative`,
    /// by the Taylor series of ln(1 + u), for |u| at most 1e-3.
    function lnOnePlusOverU(uint256 d, uint256 p, bool negative) internal pure returns (uint256) {
        return lnOnePlusOverRatio(d, 10 ** p, negative);
    }

    /// ln(1 + u) / u at `ORACLE_ONE` for u = d / scale, negated when
    /// `negative`, for |u| at most 1.1e-3. Within 50 units of 1e-70: under 25
    /// terms are nonzero, each power floors a unit plus 1.1e-3 of the previous
    /// power's loss, and each divide floors one more.
    function lnOnePlusOverRatio(uint256 d, uint256 scale, bool negative) internal pure returns (uint256) {
        uint256 sum = ORACLE_ONE;
        uint256 power = ORACLE_ONE;
        for (uint256 k = 2; power > 0; k++) {
            power = Math.mulDiv(power, d, scale);
            // ln(1 - u) / -u has every term positive, ln(1 + u) / u alternates.
            if (negative || k % 2 == 1) {
                sum += power / k;
            } else {
                sum -= power / k;
            }
        }
        return sum;
    }

    /// log10(1 + u) at `ORACLE_ONE` for u = d / 10^p, negated when `negative`.
    /// Only valid while d * 1e70 / 10^p is exact, i.e. p at most 70.
    function log10OnePlus(uint256 d, uint256 p, bool negative) internal pure returns (int256) {
        uint256 u = Math.mulDiv(d, ORACLE_ONE, 10 ** p);
        int256 log = int256(Math.mulDiv(u, lnOnePlusOverU(d, p, negative), ORACLE_LN10));
        return negative ? -log : log;
    }

    /// 10^x at `ORACLE_ONE` for |x| at most 1e-3, x at `ORACLE_ONE`, by the
    /// Taylor series of e^(x ln 10).
    function exp10Small(int256 x) internal pure returns (uint256) {
        bool negative = x < 0;
        uint256 y = Math.mulDiv(uint256(negative ? -x : x), ORACLE_LN10, ORACLE_ONE);
        uint256 sum = ORACLE_ONE;
        uint256 term = ORACLE_ONE;
        for (uint256 k = 1; term > 0; k++) {
            term = Math.mulDiv(term, y, ORACLE_ONE * k);
            if (negative && k % 2 == 1) {
                sum -= term;
            } else {
                sum += term;
            }
        }
        return sum;
    }

    /// ln(x / ORACLE_ONE) at `ORACLE_ONE` for x in [ORACLE_ONE, 2 ORACLE_ONE),
    /// by 2 atanh((x - 1) / (x + 1)).
    function lnNearOne(uint256 x) internal pure returns (uint256) {
        uint256 z = Math.mulDiv(x - ORACLE_ONE, ORACLE_ONE, x + ORACLE_ONE);
        uint256 zSquared = Math.mulDiv(z, z, ORACLE_ONE);
        uint256 term = z;
        uint256 sum = 0;
        for (uint256 k = 1; term > 0; k += 2) {
            sum += term / k;
            term = Math.mulDiv(term, zSquared, ORACLE_ONE);
        }
        return 2 * sum;
    }

    /// log10(coefficient 10^exponent) for a positive coefficient, as
    /// characteristic + fraction / `ORACLE_ONE`, fraction in [0, ORACLE_ONE),
    /// within 1e-67.
    ///
    /// In units of 1e-70: the mantissa x in [1, 2) is within 4 below after its
    /// floor and up to three halvings, so z = (x - 1) / (x + 1), at most 1/3,
    /// is within 3 and 2 atanh(z) within 6.75. z^2 is within 3, so each
    /// power of z^2 is within 3 and each of the at most 74 terms within 4
    /// after its divide, 592 doubled. The truncated ln 2 adds 3, and dividing
    /// by ln 10, itself under 1e-70 relative low, leaves under 265.
    function log10(uint256 coefficient, int256 exponent) internal pure returns (int256, uint256) {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 lead = uint256(digits(u512(coefficient))) - 1;
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 characteristic = int256(lead) + exponent;
        uint256 mantissa = lead <= 70 ? coefficient * 10 ** (70 - lead) : coefficient / 10 ** (lead - 70);
        uint256 halvings = 0;
        while (mantissa >= 2 * ORACLE_ONE) {
            mantissa /= 2;
            halvings++;
        }
        uint256 fraction = Math.mulDiv(halvings * ORACLE_LN2 + lnNearOne(mantissa), ORACLE_ONE, ORACLE_LN10);
        if (fraction >= ORACLE_ONE) {
            fraction -= ORACLE_ONE;
            characteristic += 1;
        }
        return (characteristic, fraction);
    }

    /// 10^(signedCoefficient 10^exponent) as power 10^powerExponent, power in
    /// [ORACLE_ONE, 10 ORACLE_ONE], within 1e-67 relative, for an integer part
    /// that fits int256.
    ///
    /// Relative, in units of 1e-70: the fraction f floors under a unit, 2.31
    /// of the power. y = f ln 10 / 16, at most 0.144, is within 2 below, so
    /// e^y within 2.4. Each of the at most 45 Taylor terms floors a unit plus
    /// 0.144 of the previous term's loss, under 53. Four squarings each double
    /// the error and floor a unit: 16 (2.31 + 2.4 + 53) + 15, under 1e-67.
    function exp10(int256 signedCoefficient, int256 exponent) internal pure returns (uint256, int256) {
        int256 integer;
        uint256 fraction;
        if (exponent >= 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            integer = signedCoefficient * int256(10 ** uint256(exponent));
        } else if (exponent >= -76) {
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 unit = int256(10 ** uint256(-exponent));
            integer = signedCoefficient / unit;
            int256 remainder = signedCoefficient % unit;
            if (remainder < 0) {
                integer -= 1;
                remainder += unit;
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            fraction = Math.mulDiv(uint256(remainder), ORACLE_ONE, uint256(unit));
        } else {
            // |x| is below 1, and its digits past 1e-70 are dropped.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 shift = uint256(-70 - exponent);
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 magnitude = signedCoefficient < 0 ? uint256(-signedCoefficient) : uint256(signedCoefficient);
            fraction = shift > 77 ? 0 : magnitude / 10 ** shift;
            if (signedCoefficient < 0 && fraction > 0) {
                integer = -1;
                fraction = ORACLE_ONE - fraction;
            }
        }
        uint256 reduced = Math.mulDiv(fraction, ORACLE_LN10, ORACLE_ONE << 4);
        uint256 sum = ORACLE_ONE;
        uint256 term = ORACLE_ONE;
        for (uint256 k = 1; term > 0; k++) {
            term = Math.mulDiv(term, reduced, ORACLE_ONE * k);
            sum += term;
        }
        for (uint256 i = 0; i < 4; i++) {
            sum = Math.mulDiv(sum, sum, ORACLE_ONE);
        }
        return (sum, integer - 70);
    }
}
