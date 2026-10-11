// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// Exact integer helpers for the Halmos proofs. 512-bit values are `(hi, lo)`
/// pairs. Products split into 128-bit limbs, so every word multiply is exact
/// and a symbolic operand only ever meets a constant one.
library LibHalmosExact {
    uint256 internal constant MASK128 = type(uint128).max;

    /// x * y as 512 bits.
    function mul(uint256 x, uint256 y) internal pure returns (uint256 hi, uint256 lo) {
        unchecked {
            uint256 xh = x >> 128;
            uint256 xl = x & MASK128;
            uint256 yh = y >> 128;
            uint256 yl = y & MASK128;
            uint256 ll = xl * yl;
            uint256 lh = xl * yh;
            uint256 hl = xh * yl;
            // Each term is under 2^128, so mid is under 3 * 2^128.
            uint256 mid = (ll >> 128) + (lh & MASK128) + (hl & MASK128);
            lo = (ll & MASK128) | (mid << 128);
            hi = xh * yh + (lh >> 128) + (hl >> 128) + (mid >> 128);
        }
    }

    /// (hi, lo) + y; the callers' sums are under 2^512.
    function add(uint256 hi, uint256 lo, uint256 y) internal pure returns (uint256, uint256) {
        unchecked {
            uint256 sum = lo + y;
            return (hi + (sum < lo ? 1 : 0), sum);
        }
    }

    /// (hi, lo) - y for y at most (hi, lo).
    function sub(uint256 hi, uint256 lo, uint256 y) internal pure returns (uint256, uint256) {
        unchecked {
            return (hi - (y > lo ? 1 : 0), lo - y);
        }
    }

    /// y - (hi, lo) for (hi, lo) at most y, so hi is zero.
    function rsub(uint256 y, uint256, uint256 lo) internal pure returns (uint256, uint256) {
        unchecked {
            return (0, y - lo);
        }
    }

    function lt(uint256 ah, uint256 al, uint256 bh, uint256 bl) internal pure returns (bool) {
        return ah < bh || (ah == bh && al < bl);
    }

    function abs(int256 x) internal pure returns (uint256) {
        unchecked {
            // forge-lint: disable-next-line(unsafe-typecast)
            return x < 0 ? uint256(-x) : uint256(x);
        }
    }

    /// Rebuilds x's low `bits` bits one branch per bit, so the result is a
    /// constant on every path and `10 ** result` is a constant too.
    function concrete(uint256 x, uint256 bits) internal pure returns (uint256 y) {
        for (uint256 i = 0; i < bits; i++) {
            if ((x >> i) & 1 != 0) {
                y += 2 ** i;
            }
        }
    }

    /// |rc| 10^re == |sc| 10^se with equal signs, for nonzero rc and sc whose
    /// exponent difference is a constant on the path.
    function eqValue(int256 rc, int256 re, int256 sc, int256 se) internal pure returns (bool) {
        if (rc == 0 || sc == 0) {
            return rc == sc;
        }
        if ((rc < 0) != (sc < 0)) {
            return false;
        }
        uint256 r = abs(rc);
        uint256 s = abs(sc);
        unchecked {
            if (re >= se) {
                // forge-lint: disable-next-line(unsafe-typecast)
                uint256 d = uint256(re - se);
                // r >= 1, so r 10^d >= 10^78 > 2^256 > s.
                if (d > 77) return false;
                (uint256 hi, uint256 lo) = mul(r, 10 ** d);
                return hi == 0 && lo == s;
            } else {
                // forge-lint: disable-next-line(unsafe-typecast)
                uint256 d = uint256(se - re);
                if (d > 77) return false;
                (uint256 hi, uint256 lo) = mul(s, 10 ** d);
                return hi == 0 && lo == r;
            }
        }
    }
}
