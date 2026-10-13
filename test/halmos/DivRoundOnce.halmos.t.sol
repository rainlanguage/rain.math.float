// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {DivisionByZero, ExponentOverflow, ExponentUnderflow, MulDivOverflow} from "src/error/ErrDecimalFloat.sol";
import {LibHalmosExact} from "test/halmos/LibHalmosExact.sol";
import {LibHalmosGrid} from "test/halmos/LibHalmosGrid.sol";

/// Halmos proof of SPEC.md's div and inv rules.
contract DivRoundOnceHalmosTest {
    /// floor(int256.max / 10).
    uint256 internal constant T10 = uint256(type(int256).max) / 10;
    int256 internal constant FMIN = type(int32).min;
    int256 internal constant FMAX = type(int32).max;

    function div(Float a, Float b) external pure returns (Float) {
        return LibDecimalFloat.div(a, b);
    }

    function inv(Float f) external pure returns (Float) {
        return LibDecimalFloat.inv(f);
    }

    function implDiv(int256 ca, int256 ea, int256 cb, int256 eb) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.div(ca, ea, cb, eb);
    }

    function mulDiv(uint256 x, uint256 y, uint256 d) external pure returns (uint256) {
        return LibDecimalFloatImplementation.mulDiv(x, y, d);
    }

    /// DIVZERO: a zero divisor, at any exponent, reverts
    /// `DivisionByZero(c_a, e_a)` for every Float a.
    function check_divByZero(bytes32 a, uint32 eb) external view {
        Float fa = Float.wrap(a);
        (int256 ca, int256 ea) = LibHalmosGrid.parts(fa);
        try this.div(fa, Float.wrap(bytes32(uint256(eb) << 224))) returns (Float) {
            assert(false);
        } catch (bytes memory err) {
            assert(LibHalmosGrid.bytesEq(err, abi.encodeWithSelector(DivisionByZero.selector, ca, ea)));
        }
    }

    /// ZERODIV: 0 / b is FLOAT_ZERO, all bits zero, for every non-zero b and
    /// every exponent of the zero.
    function check_zeroDividend(uint32 ea, bytes32 b) external view {
        (int256 cb,) = LibHalmosGrid.parts(Float.wrap(b));
        if (cb == 0) return;
        try this.div(Float.wrap(bytes32(uint256(ea) << 224)), Float.wrap(b)) returns (Float r) {
            assert(Float.unwrap(r) == bytes32(0));
        } catch {
            assert(false);
        }
    }

    /// INVZERO: inv of a zero at any exponent e reverts
    /// `DivisionByZero(0, e)`.
    function check_invZero(uint32 e) external view {
        try this.inv(Float.wrap(bytes32(uint256(e) << 224))) returns (Float) {
            assert(false);
        } catch (bytes memory err) {
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 se = int256(int32(e));
            assert(LibHalmosGrid.bytesEq(err, abi.encodeWithSelector(DivisionByZero.selector, int256(0), se)));
        }
    }

    /// MULDIV0 (#486): a zero denominator reverts `MulDivOverflow(x, y, 0)`
    /// for every x and y.
    function check_mulDivZeroDenominator(uint256 x, uint256 y) external view {
        try this.mulDiv(x, y, 0) returns (uint256) {
            assert(false);
        } catch (bytes memory err) {
            assert(LibHalmosGrid.bytesEq(err, abi.encodeWithSelector(MulDivOverflow.selector, x, y, uint256(0))));
        }
    }

    /// floor(x y / d) for d > 0: r d <= x y < r d + d, or the revert when
    /// that is 2^256 or more, which is x y >= d 2^256, which is hi >= d.
    function checkMulDiv(uint256 x, uint256 y, uint256 d) internal view {
        (uint256 hi, uint256 lo) = LibHalmosGrid.mul512(x, y);
        try this.mulDiv(x, y, d) returns (uint256 r) {
            (uint256 rh, uint256 rl) = LibHalmosGrid.mul512(r, d);
            assert(LibHalmosGrid.le512(rh, rl, hi, lo));
            (uint256 sh, uint256 sl) = LibHalmosGrid.add512(rh, rl, d);
            assert(!LibHalmosGrid.le512(sh, sl, hi, lo));
        } catch (bytes memory err) {
            assert(hi >= d);
            assert(LibHalmosGrid.bytesEq(err, abi.encodeWithSelector(MulDivOverflow.selector, x, y, d)));
        }
    }

    /// MULDIV: every x, y and non-zero d.
    function check_mulDivFloor(uint256 x, uint256 y, uint256 d) external view {
        if (d == 0) return;
        checkMulDiv(x, y, d);
    }

    /// MULDIVQ: the `div` operands, x and d maximized magnitudes in
    /// (T10, 10 T10] and y = 10^t the largest power of ten not above d.
    function check_mulDivDivOperands(uint256 x, uint256 d, bool t76) external view {
        uint256 y = t76 ? 1e76 : 1e75;
        if (x <= T10 || x > 10 * T10 || d <= T10 || d > 10 * T10) return;
        if (d < y || d / 10 >= y) return;
        checkMulDiv(x, y, d);
    }

    /// MULDIVREV: every x, y and non-zero d revert exactly when
    /// floor(x y / d) >= 2^256, with `MulDivOverflow(x, y, d)`.
    function check_mulDivRevert(uint256 x, uint256 y, uint256 d) external view {
        if (d == 0) return;
        (uint256 hi,) = LibHalmosGrid.mul512(x, y);
        try this.mulDiv(x, y, d) returns (uint256) {
            assert(hi < d);
        } catch (bytes memory err) {
            assert(hi >= d);
            assert(LibHalmosGrid.bytesEq(err, abi.encodeWithSelector(MulDivOverflow.selector, x, y, d)));
        }
    }

    function isMaximized(int256 m) internal pure returns (bool) {
        uint256 x = LibHalmosExact.abs(m);
        return m != type(int256).min && x > T10 && x <= 10 * T10;
    }

    /// 10^j <= |c| < 10^(j + 1).
    function hasDigits(int256 c, uint256 j) internal pure returns (bool) {
        uint256 x = LibHalmosExact.abs(c);
        return c != 0 && x >= 10 ** j && x < 10 ** (j + 1);
    }

    /// DIVQ: for maximized A at eA and B at eB, the exponents a Float's
    /// maximize gives, `Impl.div` is A 10^eA / (B 10^eB) truncated toward
    /// zero at 10^(eA - lb), lb = eB + t the exponent of B's leading digit:
    /// sign(A B) floor(|A| 10^t / |B|) at eA - eB - t, where the floor is
    /// `mulDiv(|A|, 10^t, |B|)` (MULDIVQ). The returns on mulDiv's result
    /// drop nothing by MULDIVQ: it does not revert and is in
    /// [floor(|A| / 10), |A|], inside [1, int256.max].
    /// Sliced by the operand signs; the four slices cover every pair.
    function checkDivQuotient(int256 a, int256 ea, int256 b, int256 eb, bool aNeg, bool bNeg) internal view {
        if ((a < 0) != aNeg || (b < 0) != bNeg) return;
        if (!isMaximized(a) || !isMaximized(b)) return;
        if (!LibHalmosExact.divHint(a, 1e75) || !LibHalmosExact.divHint(b, 1e75)) return;
        if (ea < FMIN - 76 || ea > FMAX - 8 || eb < FMIN - 76 || eb > FMAX - 8) return;
        uint256 xa = LibHalmosExact.abs(a);
        uint256 xb = LibHalmosExact.abs(b);
        bool t76 = xb >= 1e76;
        uint256 m;
        try this.mulDiv(xa, t76 ? 1e76 : 1e75, xb) returns (uint256 r) {
            m = r;
        } catch {
            return;
        }
        if (m == 0 || m > uint256(type(int256).max)) return;
        try this.implDiv(a, ea, b, eb) returns (int256 c, int256 e) {
            assert(e == ea - eb - (t76 ? int256(76) : int256(75)));
            // forge-lint: disable-next-line(unsafe-typecast)
            assert(c == ((a < 0) == (b < 0) ? int256(m) : -int256(m)));
        } catch {
            assert(false);
        }
    }

    function check_divQuotientPosPos(int256 a, int256 ea, int256 b, int256 eb) external view {
        checkDivQuotient(a, ea, b, eb, false, false);
    }

    function check_divQuotientPosNeg(int256 a, int256 ea, int256 b, int256 eb) external view {
        checkDivQuotient(a, ea, b, eb, false, true);
    }

    function check_divQuotientNegPos(int256 a, int256 ea, int256 b, int256 eb) external view {
        checkDivQuotient(a, ea, b, eb, true, false);
    }

    function check_divQuotientNegNeg(int256 a, int256 ea, int256 b, int256 eb) external view {
        checkDivQuotient(a, ea, b, eb, true, true);
    }

    /// SPILL (#458). For every non-zero int256 a and b, one digit-count pair
    /// per path, with ea <= int256.min + 2^253 and eb >= int256.max - 2^253:
    /// eb - ea >= 2^256 - 1 - 2^254, so |a / b| < 10^77 10^(ea - eb) is below
    /// 10^int256.min, no digit is left at the int256.min floor, and the rule
    /// (`Impl.div` NatSpec) is (0, 0).
    ///
    /// Every input reaching the spill branch is in this region. It needs
    /// eA' - int256.min < adjust <= 76 + 76 (shortfalls are in [0, 76]) for
    /// the maximized eA', so ea < int256.min + 228 (maximize shifts at most 76,
    /// and a non-zero shortfall means ea < int256.min + 76), and the maximized
    /// eB' > int256.max - 152, which is not the int256.min a shortfall gives,
    /// so eb >= eB' > int256.max - 152.
    function checkSpill(int256 a, int256 ea, int256 b, int256 eb, uint256 jaBits, uint256 jbBits) internal view {
        uint256 ja = LibHalmosExact.concrete(jaBits, 7);
        uint256 jb = LibHalmosExact.concrete(jbBits, 7);
        if (ja > 76 || jb > 76) return;
        if (!hasDigits(a, ja) || !hasDigits(b, jb)) return;
        if (!LibHalmosExact.maximizeHints(a, ja) || !LibHalmosExact.maximizeHints(b, jb)) return;
        if (ea > type(int256).min + 2 ** 253 || eb < type(int256).max - 2 ** 253) return;
        try this.implDiv(a, ea, b, eb) returns (int256 c, int256 e) {
            assert(c == 0 && e == 0);
        } catch {
            assert(false);
        }
    }

    function check_divSpill(int256 a, int256 ea, int256 b, int256 eb, uint256 jaBits, uint256 jbBits)
        external
        view
    {
        checkSpill(a, ea, b, eb, jaBits, jbBits);
    }

    /// The finishing rule: `result` is T(c 10^e), reverting `ExponentUnderflow`
    /// with (ci, ei) where T is zero and `ExponentOverflow` with (ci, ei) where
    /// T is past every Float, or never overflowing when `overflows` is false.
    function checkFinish(
        bool ok,
        bytes memory out,
        int256 c,
        int256 e,
        int256 ci,
        int256 ei,
        bool overflows
    ) internal pure {
        (uint256 m, int256 f, uint256 status) = LibHalmosGrid.truncGrid(c, e);
        if (ok) {
            assert(status == 0);
            assert(out.length == 32);
            (int256 rc, int256 re) = LibHalmosGrid.parts(abi.decode(out, (Float)));
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 expected = c < 0 ? -int256(m) : int256(m);
            assert(LibHalmosExact.eqValue(rc, re, expected, f));
        } else if (status == 1) {
            assert(LibHalmosGrid.bytesEq(out, abi.encodeWithSelector(ExponentUnderflow.selector, ci, ei)));
        } else if (status == 2 && overflows) {
            assert(LibHalmosGrid.bytesEq(out, abi.encodeWithSelector(ExponentOverflow.selector, ci, ei)));
        } else {
            assert(false);
        }
    }

    /// The digit count j + 1 of a non-zero Float coefficient c, one j per
    /// path, false when the path's j is not c's. Every non-zero |c| <= 2^223
    /// < 10^68 has one j in [0, 67], and `maximizeHints` holds for it.
    function digits(int256 c, uint256 jBits) internal pure returns (bool) {
        uint256 j = LibHalmosExact.concrete(jBits, 7);
        return j <= 67 && hasDigits(c, j) && LibHalmosExact.maximizeHints(c, j);
    }

    /// DIVFIN: for Floats a and b, digit counts one pair per path, `div(a, b)`
    /// is T(c 10^e) for (c, e) = `Impl.div(a, b)`, its range errors reporting
    /// a. `lo` and `hi` bound e, the slice.
    function checkDivFinish(Float a, Float b, int256 lo, int256 hi) internal view {
        (int256 ca, int256 ea) = LibHalmosGrid.parts(a);
        (int256 cb, int256 eb) = LibHalmosGrid.parts(b);
        try this.implDiv(ca, ea, cb, eb) returns (int256 c, int256 e) {
            if (e < lo || e > hi) return;
            (bool ok, bytes memory out) = address(this).staticcall(abi.encodeCall(this.div, (a, b)));
            checkFinish(ok, out, c, e, ca, ea, true);
        } catch {
            assert(false);
        }
    }

    /// DIVFIN, e in [int32.min + 1, int32.max - 11].
    function check_divFinishMid(int224 ca, int32 ea, int224 cb, int32 eb, uint256 jaBits, uint256 jbBits)
        external
        view
    {
        if (!digits(ca, jaBits) || !digits(cb, jbBits)) return;
        checkDivFinish(LibHalmosGrid.float(ca, ea), LibHalmosGrid.float(cb, eb), FMIN + 1, FMAX - 11);
    }

    /// INVFIN: for a Float f, digit count one per path, `inv(f)` is
    /// T(c 10^e) for (c, e) = `Impl.div(1e76, -76, f)`, 1 / f by DIVQ, its
    /// underflow reporting f, and never overflows.
    function checkInvFinish(Float f, int256 lo, int256 hi) internal view {
        (int256 cf, int256 ef) = LibHalmosGrid.parts(f);
        try this.implDiv(1e76, -76, cf, ef) returns (int256 c, int256 e) {
            if (e < lo || e > hi) return;
            (bool ok, bytes memory out) = address(this).staticcall(abi.encodeCall(this.inv, (f)));
            checkFinish(ok, out, c, e, cf, ef, false);
        } catch {
            assert(false);
        }
    }

    /// INVFIN, e in [int32.min + 1, int32.max - 11].
    function check_invFinishMid(int224 cf, int32 ef, uint256 jBits) external view {
        if (!digits(cf, jBits)) return;
        checkInvFinish(LibHalmosGrid.float(cf, ef), FMIN + 1, FMAX - 11);
    }
}
