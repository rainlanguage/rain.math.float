// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibHalmosExact} from "test/halmos/LibHalmosExact.sol";

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
/// Composition: by MAX and IDEM, NEAR/FAR apply to S. They put c 10^e at or
/// below |S| and S below the next multiple of 10^e. A grid member above
/// |c| 10^e and at most |S| would be m 10^f with either f >= e, a multiple of
/// 10^e strictly between |c| 10^e and (|c| + 1) 10^e, which none is, or f < e,
/// so m 10^f <= 2^223 10^(e - 1) <= |c| 10^e, not above it. So T(S) =
/// T(c 10^e), unbounded exponents included, and PACK makes that the result.
contract AddSubRoundOnceHalmosTest {
    /// floor(int256.max / 10).
    uint256 internal constant T10 = uint256(type(int256).max) / 10;
    uint256 internal constant TWO_223 = 2 ** 223;
    int256 internal constant FMIN = type(int32).min;
    int256 internal constant FMAX = type(int32).max;

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
        return m != type(int256).min && x > T10 && x <= 10 * T10;
    }

    /// ZERO.
    function check_addZeroOperand(int256 c, int256 e, int256 ez, bool zeroFirst) external view {
        try this.implAdd(zeroFirst ? int256(0) : c, zeroFirst ? ez : e, zeroFirst ? c : int256(0), zeroFirst ? e : ez)
        returns (int256 rc, int256 re) {
            assert(rc == c);
            assert(c == 0 || re == e);
        } catch {
            assert(false);
        }
    }

    /// MINUS.
    function check_subIsAddNegated(int224 cb, int256 ca, int256 ea, int256 eb) external view {
        (bool subOk, bytes memory subOut) = address(this).staticcall(abi.encodeCall(this.implSub, (ca, ea, cb, eb)));
        (bool addOk, bytes memory addOut) =
            address(this).staticcall(abi.encodeCall(this.implAdd, (ca, ea, -int256(cb), eb)));
        assert(subOk == addOk);
        assert(subOut.length == addOut.length);
        for (uint256 i = 0; i < subOut.length; i++) {
            assert(subOut[i] == addOut[i]);
        }
    }

    /// MAX, one shift k per path.
    function check_maximizeFloat(int256 c, int32 e) external view {
        if (c == 0 || c > 2 ** 223 || c < -(2 ** 223)) return;
        try this.maximize(c, e) returns (int256 m, int256 me, int256 shortfall) {
            assert(shortfall == 0);
            int256 k = int256(e) - me;
            assert(k >= 0 && k <= 76);
            // forge-lint: disable-next-line(unsafe-typecast)
            (uint256 hi, uint256 lo) = LibHalmosExact.mul(LibHalmosExact.abs(c), 10 ** uint256(k));
            assert(hi == 0 && lo == LibHalmosExact.abs(m));
            assert((m < 0) == (c < 0));
            assert(isMaximized(m));
            assert(m % 1e8 == 0);
        } catch {
            assert(false);
        }
    }

    /// IDEM.
    function check_maximizeIdempotent(int256 m, int256 e) external view {
        if (!isMaximized(m)) return;
        try this.maximize(m, e) returns (int256 rm, int256 re, int256 shortfall) {
            assert(rm == m && re == e && shortfall == 0);
        } catch {
            assert(false);
        }
    }

    /// The add result against the exact sum S = A 10^D + B, in units of
    /// 10^eB. `t` is the result's exponent less eB.
    function checkSum(int256 a, int256 b, uint256 d, int256 c, uint256 t) internal pure {
        uint256 ma = LibHalmosExact.abs(a);
        uint256 mb = LibHalmosExact.abs(b);
        // |S| / 10^eB as 512 bits, and S's sign.
        (uint256 vh, uint256 vl) = LibHalmosExact.mul(ma, 10 ** d);
        bool negative;
        if ((a < 0) == (b < 0)) {
            (vh, vl) = LibHalmosExact.add(vh, vl, mb);
            negative = a < 0;
        } else if (LibHalmosExact.lt(vh, vl, 0, mb)) {
            (vh, vl) = LibHalmosExact.rsub(mb, vh, vl);
            negative = b < 0;
        } else {
            (vh, vl) = LibHalmosExact.sub(vh, vl, mb);
            negative = a < 0;
        }
        uint256 mc = LibHalmosExact.abs(c);
        if (vh == 0 && vl == 0) {
            assert(c == 0);
            return;
        }
        assert(c != 0 && (c < 0) == negative);
        (uint256 lh, uint256 ll) = LibHalmosExact.mul(mc, 10 ** t);
        (uint256 uh, uint256 ul) = LibHalmosExact.add(lh, ll, 10 ** t);
        // |c| 10^t <= |S| < (|c| + 1) 10^t.
        assert(!LibHalmosExact.lt(vh, vl, lh, ll));
        assert(LibHalmosExact.lt(vh, vl, uh, ul));
        // Exact, or no grid member below 10^t lies above |c| 10^t.
        assert((vh == lh && vl == ll) || mc >= TWO_223 / 10 + 1);
    }

    /// NEAR: gap D in [0, 76], one D per path.
    function check_addNear(int256 a, int256 b, int256 eB, uint256 dBits, bool swap) external view {
        uint256 d = LibHalmosExact.concrete(dBits, 7);
        if (d > 76) return;
        if (!isMaximized(a) || !isMaximized(b) || a % 1e8 != 0 || b % 1e8 != 0) return;
        if (eB < FMIN - 76 || eB > FMAX - 8) return;
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
        if (eB < FMIN - 76 || eB > FMAX - 8) return;
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 eA = eB + int256(d);
        if (eA > FMAX - 8) return;
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
