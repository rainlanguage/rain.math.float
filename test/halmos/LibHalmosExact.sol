// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";

Vm constant VM = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

/// Exact integer helpers for the Halmos proofs. Every multiply has an operand
/// that is constant on the path, so halmos never makes it uninterpreted.
library LibHalmosExact {
    /// floor(int256.max / 10).
    uint256 internal constant T10 = uint256(type(int256).max) / 10;
    /// The Float exponent range.
    int256 internal constant FMIN = type(int32).min;
    int256 internal constant FMAX = type(int32).max;

    /// Whether case `i` of a lemma's case split is in this run's slice
    /// [HALMOS_SLICE_LO, HALMOS_SLICE_HI], every case when unset. A lemma
    /// returns for a case outside it; the slices of each lemma in
    /// `.github/workflows/halmos.yaml` tile its whole case range.
    function inSlice(uint256 i) internal view returns (bool) {
        return i >= VM.envOr("HALMOS_SLICE_LO", uint256(0)) && i <= VM.envOr("HALMOS_SLICE_HI", type(uint256).max);
    }

    /// Whether any case in [lo, hi] is in this run's slice, so a lemma can
    /// drop a whole block of cases before splitting the next index.
    function overlapsSlice(uint256 lo, uint256 hi) internal view returns (bool) {
        return hi >= VM.envOr("HALMOS_SLICE_LO", uint256(0)) && lo <= VM.envOr("HALMOS_SLICE_HI", type(uint256).max);
    }

    function abs(int256 x) internal pure returns (uint256) {
        unchecked {
            // forge-lint: disable-next-line(unsafe-typecast)
            return x < 0 ? uint256(-x) : uint256(x);
        }
    }

    /// True for every int256 x and positive d: x / d is zero iff |x| < d.
    /// Halmos branches on division as an uninterpreted function, so a lemma
    /// that returns when this is false excludes no input and gives the branch
    /// solver the fact for the term x / d.
    function divHint(int256 x, int256 d) internal pure returns (bool) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return (x / d == 0) == (abs(x) < uint256(d));
    }

    /// For 10^j <= |c| < 10^(j + 1), s = 0 or s + j < 76, and t <= 76 (so
    /// 10^t is a positive int256), |c| 10^s lies in [10^(s + j), 10^(s + j + 1))
    /// inside int256, so c 10^s / 10^t is zero iff s + j < t. True for every
    /// such c.
    function shiftHint(int256 c, uint256 s, uint256 j, uint256 t) internal pure returns (bool) {
        int256 p = c;
        if (s > 0) {
            unchecked {
                // forge-lint: disable-next-line(unsafe-typecast)
                p = c * int256(10 ** s);
            }
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return (p / int256(10 ** t) == 0) == (s + j < t);
    }

    /// For 10^j <= |c| < 10^(j + 1) and s = 0 or s + j < 76, c 10^s is in
    /// [-T10, T10] iff |c| <= floor(T10 / 10^s), and adding T10 maps that
    /// range onto [0, 2 T10] without wrapping. True for every such c.
    function timesTenHint(int256 c, uint256 s) internal pure returns (bool) {
        int256 p = c;
        if (s > 0) {
            unchecked {
                // forge-lint: disable-next-line(unsafe-typecast)
                p = c * int256(10 ** s);
            }
        }
        bool fits;
        unchecked {
            // forge-lint: disable-next-line(unsafe-typecast)
            fits = uint256(p) + T10 < 2 * T10 + 1;
        }
        return fits == (abs(c) <= T10 / 10 ** s);
    }

    /// `shiftHint` for each division `maximize` makes on a c with
    /// 10^j <= |c| < 10^(j + 1): by 10^75, then 10^38, 10^57, 10^66, 10^74
    /// (repeated) and 10^75 on c times the shift so far, and `timesTenHint`
    /// for its final fits-times-ten test. True for every such c, so a lemma
    /// that returns when it is false excludes no input; the tracked shift
    /// only picks which terms get the fact, and a wrong pick costs
    /// completeness (a loop-bound warning or extra paths), never soundness.
    function maximizeHints(int256 c, uint256 j) internal pure returns (bool) {
        if (!shiftHint(c, 0, j, 75)) return false;
        if (j >= 75) return timesTenHint(c, 0);
        uint256 s = 0;
        if (!shiftHint(c, s, j, 38)) return false;
        if (s + j < 38) s += 38;
        if (!shiftHint(c, s, j, 57)) return false;
        if (s + j < 57) s += 19;
        if (!shiftHint(c, s, j, 66)) return false;
        if (s + j < 66) s += 10;
        while (true) {
            if (!shiftHint(c, s, j, 74)) return false;
            if (s + j >= 74) break;
            s += 2;
        }
        if (!shiftHint(c, s, j, 75)) return false;
        if (s + j < 75) s += 1;
        return timesTenHint(c, s);
    }

    /// 10^j <= |c| < 10^(j + 1), or c zero for j = 77. Every int256 has one j
    /// in [0, 77].
    function hasDigits(int256 c, uint256 j) internal pure returns (bool) {
        if (j == 77) return c == 0;
        uint256 x = abs(c);
        return c != 0 && x >= 10 ** j && x < 10 ** (j + 1);
    }

    /// For 10^n <= |c| < 10^(n + 1) (n is c's digit index, one below its
    /// digit count), the digit index of each quotient
    /// `LibDecimalFloat.packLossy` takes of c while shedding digits to fit
    /// int224: c / 1e72 and c / 1e75 are zero iff n < 72 and n < 75, the cut
    /// leaves a quotient of index n - 8 (n >= 75), n - 5 (n >= 72) or n, and
    /// each further division by ten one less; each is |c| / 10^k in magnitude
    /// for the k digits shed. The shedding ends at the first quotient that
    /// fits int224, which every quotient of index at most 66 (67 digits) does.
    /// True for every such c, so a lemma that returns when it is false
    /// excludes no input; it bounds the shedding loop on every path.
    function packHints(int256 c, uint256 n) internal pure returns (bool) {
        if ((c / 1e72 == 0) != (n < 72)) return false;
        int256 x = c;
        uint256 m = n;
        if (n >= 72) {
            if ((c / 1e75 == 0) != (n < 75)) return false;
            if (n >= 75) {
                x = c / 1e8;
                m = n - 8;
            } else {
                x = c / 1e5;
                m = n - 5;
            }
        }
        while (m >= 67) {
            if (!isQuotient(c, x, n, m)) return false;
            // forge-lint: disable-next-line(unsafe-typecast)
            if (int224(x) == x) return true;
            x /= 10;
            m--;
        }
        return isQuotient(c, x, n, m);
    }

    /// x has digit index m, c's sign and |c| / 10^(n - m) as its magnitude.
    function isQuotient(int256 c, int256 x, uint256 n, uint256 m) private pure returns (bool) {
        return hasDigits(x, m) && (x < 0) == (c < 0) && abs(x) == abs(c) / 10 ** (n - m);
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

    /// |rc| 10^re == |sc| 10^se with equal signs. The exponent difference is
    /// rebuilt by `concrete`, so `10 ** d` is a constant on every path.
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
                uint256 p = 10 ** concrete(d, 7);
                return r <= type(uint256).max / p && r * p == s;
            } else {
                // forge-lint: disable-next-line(unsafe-typecast)
                uint256 d = uint256(se - re);
                if (d > 77) return false;
                uint256 p = 10 ** concrete(d, 7);
                return s <= type(uint256).max / p && s * p == r;
            }
        }
    }
}
