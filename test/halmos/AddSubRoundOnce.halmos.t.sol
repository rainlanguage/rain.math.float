// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloatImplementation} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibHalmosExact} from "./LibHalmosExact.sol";

/// Halmos proof that `LibDecimalFloat.add` and `sub` return the exact sum
/// rounded once toward zero, then packed (#350, #434, #436), for every pair of
/// Floats.
///
/// For Floats a = ca 10^ea, b = cb 10^eb, S = a + b exactly, and G the Float
/// grid (int224 magnitudes, int32 exponents), the rule is: the result is
/// T(S), the member of G nearest S not exceeding it in magnitude, reverting
/// `ExponentUnderflow` when that is zero for nonzero S and `ExponentOverflow`
/// when it needs an exponent past int32.max. `sub(a, b)` is S = a - b, with b
/// negated exactly.
///
/// `add(a, b)` is `packArithmeticResult(Impl.add(ca, ea, cb, eb))`, and the
/// whole property is too large for one query (symbolic `10 **` exponents are
/// uninterpreted), so it is the composition of these lemmas:
///
/// - ZERO: a zero operand returns the other operand's parts, whose value is S.
/// - MINUS: `Impl.sub(ca, ea, cb, eb)` is `Impl.add(ca, ea, -cb, eb)` for an
///   int224 cb, so sub is add over coefficients in [-2^223, 2^223].
/// - MAX: for c in [-2^223, 2^223] nonzero and e an int32, `maximize(c, e)`
///   is (M, e - k, 0) with M = c 10^k exactly, T10 < |M| <= 10 T10 for
///   T10 = floor(int256.max / 10), and 10^8 | M.
/// - IDEM: `maximize` returns such an M and its exponent unchanged, so
///   `Impl.add` on the maximized parts takes the same steps as on the
///   original ones (its first step is that `maximize`).
/// - NEAR (exponent gap D in [0, 76]) and FAR (D > 76): for maximized A at
///   eA = eB + D and B at eB, `Impl.add` in either argument order returns
///   (c, e) with |c| 10^e <= |S| < (|c| + 1) 10^e, c of S's sign (zero iff S
///   is), and either c 10^e = S or 10 |c| >= 2^223.
/// - PACK (`PackArithmeticResult.halmos.t.sol`): `packArithmeticResult(c, e)`
///   is T(c 10^e) with T's reverts.
///
/// MAX and MINUS take one digit count per path. The lemmas return early when
/// a hint filter (`divHint`, `maximizeHints`) is false, and
/// `LibHalmosExact.halmos.t.sol` proves those filters true for every input
/// they are given, so the early returns exclude nothing.
///
/// Composition: by MAX and IDEM, NEAR/FAR apply to S. They put c 10^e at or
/// below |S| and S below the next multiple of 10^e. A grid member above
/// |c| 10^e and at most |S| would be m 10^f with either f >= e, a multiple of
/// 10^e strictly between |c| 10^e and (|c| + 1) 10^e, which none is, or f < e,
/// so m 10^f <= 2^223 10^(e - 1) <= |c| 10^e, not above it. So T(S) =
/// T(c 10^e), unbounded exponents included, and PACK makes that the result.
///
/// MINUS (#513), NEAR (#512) and PACK's `check_packLow` cases 99-780 (#511) are
/// not yet proved under the halmos workflow's 5-minute limit per run and are out
/// of its matrix, so the composition is open there. The matrix runs on manual
/// dispatch: the workflow is disabled on the repository, so a `src/` change
/// re-proves nothing until someone dispatches it.
contract AddSubRoundOnceHalmosTest {
    uint256 internal constant TWO_223 = 2 ** 223;

    function implAdd(int256 ca, int256 ea, int256 cb, int256 eb) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.add(ca, ea, cb, eb);
    }

    function implSub(int256 ca, int256 ea, int256 cb, int256 eb) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.sub(ca, ea, cb, eb);
    }

    function maximize(int256 c, int256 e) external pure returns (int256, int256, int256) {
        return LibDecimalFloatImplementation.maximize(c, e);
    }

    function isMaximized(int256 m) internal pure returns (bool) {
        uint256 x = LibHalmosExact.abs(m);
        return m != type(int256).min && x > LibHalmosExact.T10 && x <= 10 * LibHalmosExact.T10;
    }

    /// ZERO.
    function check_addZeroOperand(int256 c, int256 e, int256 ez, bool zeroFirst) external view {
        try this.implAdd(
            zeroFirst ? int256(0) : c, zeroFirst ? ez : e, zeroFirst ? c : int256(0), zeroFirst ? e : ez
        ) returns (
            int256 rc, int256 re
        ) {
            assert(rc == c);
            assert(c == 0 || re == e);
        } catch {
            assert(false);
        }
    }

    /// MINUS, split by the digit counts of ca and -cb (j = 77 for zero), one
    /// pair per path. Every int256 has one j in [0, 77].
    /// Unproven under the 5-minute limit, not in the halmos workflow's matrix:
    /// see #513.
    function check_subIsAddNegated(int224 cb, int256 ca, int256 ea, int256 eb, uint256 jaBits, uint256 jbBits)
        external
        view
    {
        uint256 ja = LibHalmosExact.concrete(jaBits, 7);
        if (ja > 77 || !LibHalmosExact.overlapsSlice(ja * 78, ja * 78 + 77)) return;
        uint256 jb = LibHalmosExact.concrete(jbBits, 7);
        if (jb > 77 || !LibHalmosExact.inSlice(ja * 78 + jb)) return;
        int256 nb = -int256(cb);
        if (!LibHalmosExact.hasDigits(ca, ja) || !LibHalmosExact.hasDigits(nb, jb)) return;
        if (ja < 77 && !LibHalmosExact.maximizeHints(ca, ja)) return;
        if (jb < 77 && !LibHalmosExact.maximizeHints(nb, jb)) return;
        (bool subOk, bytes memory subOut) = address(this).staticcall(abi.encodeCall(this.implSub, (ca, ea, cb, eb)));
        (bool addOk, bytes memory addOut) = address(this).staticcall(abi.encodeCall(this.implAdd, (ca, ea, nb, eb)));
        assert(subOk == addOk);
        assert(subOut.length == addOut.length);
        for (uint256 i = 0; i < subOut.length; i++) {
            assert(subOut[i] == addOut[i]);
        }
    }

    /// MAX, split by |c|'s digit count: 10^j <= |c| < 10^(j + 1), one j per
    /// path. Every nonzero |c| <= 2^223 < 10^68 has one j in [0, 67].
    function check_maximizeFloat(int256 c, int32 e, uint256 jBits) external view {
        uint256 j = LibHalmosExact.concrete(jBits, 7);
        if (j > 67 || !LibHalmosExact.inSlice(j)) return;
        if (c == 0 || c > 2 ** 223 || c < -(2 ** 223)) return;
        uint256 x = LibHalmosExact.abs(c);
        if (x < 10 ** j || x >= 10 ** (j + 1)) return;
        if (!LibHalmosExact.maximizeHints(c, j)) return;
        try this.maximize(c, e) returns (int256 m, int256 me, int256 shortfall) {
            assert(shortfall == 0);
            int256 k = int256(e) - me;
            assert(k >= 8 && k <= 76);
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 scale = 10 ** uint256(k);
            unchecked {
                // forge-lint: disable-next-line(unsafe-typecast)
                assert(m == c * int256(scale));
            }
            // T10 < |c| 10^k <= 10 T10 <= int256.max, so c 10^k does not
            // wrap: m is c 10^k exactly (so of c's sign, and 10^8 | m as
            // k >= 8) and maximized.
            assert(x > LibHalmosExact.T10 / scale && x <= (10 * LibHalmosExact.T10) / scale);
        } catch {
            assert(false);
        }
    }

    /// IDEM.
    function check_maximizeIdempotent(int256 m, int256 e) external view {
        if (!isMaximized(m) || !LibHalmosExact.divHint(m, 1e75)) return;
        try this.maximize(m, e) returns (int256 rm, int256 re, int256 shortfall) {
            assert(rm == m && re == e && shortfall == 0);
        } catch {
            assert(false);
        }
    }

    /// The add result against the exact sum S = A 10^D + B, in units of
    /// 10^eB. `t` is the result's exponent less eB, D or D + 1, so the bounds
    /// need only F = floor(|S| / 10^D) and whether 10^D | S. With
    /// Q = trunc(B / 10^D) and R = B - Q 10^D (|R| < 10^D, B's sign),
    /// S / 10^D = A + Q + R / 10^D.
    function checkSum(int256 a, int256 b, uint256 d, int256 c, uint256 t) internal pure {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 p = int256(10 ** d);
        int256 q = b / p;
        int256 r = b % p;
        uint256 ma = LibHalmosExact.abs(a);
        uint256 f;
        bool exact = r == 0;
        bool negative = a < 0;
        if ((a < 0) == (b < 0)) {
            // |S| / 10^D = |A| + |Q| + |R| / 10^D.
            f = ma + LibHalmosExact.abs(q);
        } else if (d > 0) {
            // |S| / 10^D = |A| - |Q| - |R| / 10^D, and |Q| <= |B| / 10 <= T10
            // < |A|, so S has A's sign.
            f = ma - LibHalmosExact.abs(q) - (exact ? 0 : 1);
        } else {
            // D = 0: S = A + B.
            uint256 mb = LibHalmosExact.abs(b);
            if (ma >= mb) {
                f = ma - mb;
            } else {
                f = mb - ma;
                negative = b < 0;
            }
        }
        if (f == 0 && exact) {
            assert(c == 0);
            return;
        }
        assert(c != 0 && (c < 0) == negative);
        uint256 mc = LibHalmosExact.abs(c);
        uint256 u = t == d ? 1 : 10;
        // |c| 10^t <= |S| < (|c| + 1) 10^t, as |c| u <= F < (|c| + 1) u.
        uint256 lower = mc * u;
        assert(lower <= f);
        assert(f < lower + u);
        // Exact, or no grid member below 10^t lies above |c| 10^t.
        assert((exact && f == lower) || mc >= TWO_223 / 10 + 1);
    }

    /// NEAR: gap D in [0, 76], one D per path. B = 10 yb: by MAX 10^8 | B
    /// for every maximized B, so |yb| <= T10 drops none, and `Impl.add`'s
    /// B mod 10 is zero by construction (solvers time out deducing it from
    /// B mod 10^8 == 0).
    /// Unproven under the 5-minute limit, not in the halmos workflow's matrix:
    /// see #512.
    function check_addNear(int256 a, int256 yb, int256 eB, uint256 dBits, bool swap) external view {
        uint256 d = LibHalmosExact.concrete(dBits, 7);
        if (d > 76 || !LibHalmosExact.inSlice(d)) return;
        // forge-lint: disable-next-line(unsafe-typecast)
        if (yb < -int256(LibHalmosExact.T10) || yb > int256(LibHalmosExact.T10)) return;
        int256 b = yb * 10;
        if (!isMaximized(a) || !isMaximized(b) || a % 1e8 != 0 || b % 1e8 != 0) return;
        if (!LibHalmosExact.divHint(a, 1e75) || !LibHalmosExact.divHint(b, 1e75)) return;
        if (eB < LibHalmosExact.FMIN - 76 || eB > LibHalmosExact.FMAX - 8) return;
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 eA = eB + int256(d);
        try this.implAdd(swap ? b : a, swap ? eB : eA, swap ? a : b, swap ? eA : eB) returns (int256 c, int256 e) {
            int256 t = e - eB;
            // forge-lint: disable-next-line(unsafe-typecast)
            assert(t == int256(d) || t == int256(d) + 1);
            // forge-lint: disable-next-line(unsafe-typecast)
            checkSum(a, b, d, c, uint256(t));
        } catch {
            assert(false);
        }
    }

    /// FAR: gap D > 76. |B| < 2^255 < 10^77 <= 10^D, so 0 < |B| 10^eB <
    /// 10^eA: S lies strictly between A 10^eA and (A + sign(B)) 10^eA. Its
    /// floor at 10^eA is |A| when the signs agree and |A| - 1 when they
    /// differ, and |A| - 1 >= T10 > 2^223 / 10.
    function check_addFar(int256 a, int256 b, int256 eB, uint256 d, bool swap) external view {
        if (d <= 76 || d > 2 ** 40) return;
        if (!isMaximized(a) || !isMaximized(b) || a % 1e8 != 0 || b % 1e8 != 0) return;
        if (!LibHalmosExact.divHint(a, 1e75) || !LibHalmosExact.divHint(b, 1e75)) return;
        if (eB < LibHalmosExact.FMIN - 76 || eB > LibHalmosExact.FMAX - 8) return;
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 eA = eB + int256(d);
        if (eA > LibHalmosExact.FMAX - 8) return;
        try this.implAdd(swap ? b : a, swap ? eB : eA, swap ? a : b, swap ? eA : eB) returns (int256 c, int256 e) {
            assert(e == eA);
            uint256 mc = LibHalmosExact.abs(c);
            uint256 ma = LibHalmosExact.abs(a);
            assert((c < 0) == (a < 0));
            assert(mc == ((a < 0) == (b < 0) ? ma : ma - 1));
        } catch {
            assert(false);
        }
    }
}
