// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float, LibDecimalFloat} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {AgreeToleranceNegative, AgreeNoPositiveTolerance} from "src/error/ErrDecimalFloat.sol";
import {LibHalmosExact} from "test/halmos/LibHalmosExact.sol";

/// Halmos proofs of SPEC.md's `agree` rules.
///
/// TOLERANCE: for every four Floats, a tolerance with a negative coefficient
/// reverts `AgreeToleranceNegative(absolute, proportional)`; otherwise, neither
/// coefficient positive reverts `AgreeNoPositiveTolerance(absolute,
/// proportional)`. A Float's sign is its int224 coefficient's, whatever the
/// exponent. One query covers every input.
///
/// EITHER ORDER, spread half (#498): the spread `agree` takes of (l, h) is the
/// same coefficient and exponent as the one it takes of (h, l). The spread is
/// `Impl.sub(h, l)`, negated by `Impl.minus` when negative. With
/// `AddSubRoundOnce.halmos.t.sol`'s lemmas:
///
/// - ZERO here: a zero extreme gives the same spread in either order.
/// - MINUS: `Impl.sub(h, l)` is `Impl.add(h, -l)` for an int224 l.
/// - MAX, IDEM: for nonzero int224 x, `Impl.add` on x takes the same steps as
///   on M(x), the maximized parts.
/// - NEG here: M(-x) is -M(x) at the same exponent and shortfall.
///
/// So for nonzero l, h, with X = M(h) and Y = M(-l) = -M(l), the two spreads
/// are `minus` of `Impl.add(X, Y)` and of `Impl.add(-Y, -X)` when negative.
/// SYMNEAR (exponent gap D in [0, 76]) and SYMFAR (D > 76) prove those equal
/// for every maximized X, Y in either exponent order, over the same ranges as
/// NEAR and FAR.
///
/// The lemmas return early when a hint filter (`divHint`, `maximizeHints`) is
/// false; `LibHalmosExact.halmos.t.sol` proves both true for every input, so
/// the early returns exclude nothing. SYMNEAR is sliced by D into
/// [0, 19], [20, 39], [40, 59] and [60, 76], which together cover [0, 76].
contract AgreeHalmosTest {
    /// floor(int256.max / 10).
    uint256 internal constant T10 = uint256(type(int256).max) / 10;
    int256 internal constant FMIN = type(int32).min;
    int256 internal constant FMAX = type(int32).max;

    function agree(Float absolute, Float proportional, Float lowest, Float highest) external pure returns (bool) {
        return LibDecimalFloat.agree(absolute, proportional, lowest, highest);
    }

    function implAdd(int256 ca, int256 ea, int256 cb, int256 eb) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.add(ca, ea, cb, eb);
    }

    function implSub(int256 ca, int256 ea, int256 cb, int256 eb) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.sub(ca, ea, cb, eb);
    }

    function implMinus(int256 c, int256 e) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.minus(c, e);
    }

    function maximize(int256 c, int256 e) external pure returns (int256, int256, int256) {
        return LibDecimalFloatImplementation.maximize(c, e);
    }

    /// The low 224 bits, sign extended: SPEC's c.
    function coefficient(bytes32 f) internal pure returns (int256) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return int256(int224(uint224(uint256(f))));
    }

    /// TOLERANCE.
    function check_agreeToleranceErrors(bytes32 a, bytes32 p, bytes32 l, bytes32 h) external view {
        int256 ca = coefficient(a);
        int256 cp = coefficient(p);
        bool negative = ca < 0 || cp < 0;
        if (!negative && (ca > 0 || cp > 0)) return;
        (bool ok, bytes memory out) = address(this).staticcall(
            abi.encodeCall(this.agree, (Float.wrap(a), Float.wrap(p), Float.wrap(l), Float.wrap(h)))
        );
        assert(!ok);
        assert(out.length == 68);
        bytes4 selector = negative ? AgreeToleranceNegative.selector : AgreeNoPositiveTolerance.selector;
        bytes32 w0;
        bytes32 w1;
        bytes32 w2;
        assembly ("memory-safe") {
            w0 := mload(add(out, 0x20))
            w1 := mload(add(out, 0x24))
            w2 := mload(add(out, 0x44))
        }
        assert(bytes4(w0) == selector);
        assert(w1 == a);
        assert(w2 == p);
    }

    function spread(int256 c, int256 e) internal view returns (int256, int256) {
        if (c < 0) return this.implMinus(c, e);
        return (c, e);
    }

    /// ZERO: the spread of a zero extreme and any Float, in either order.
    function check_spreadZeroEitherOrder(int224 c, int32 e, int32 ez) external view {
        (int256 c1, int256 e1) = this.implSub(c, e, 0, ez);
        (int256 c2, int256 e2) = this.implSub(0, ez, c, e);
        (c1, e1) = spread(c1, e1);
        (c2, e2) = spread(c2, e2);
        assert(c1 == c2 && e1 == e2);
    }

    /// 10^j <= |c| < 10^(j + 1).
    function hasDigits(int256 c, uint256 j) internal pure returns (bool) {
        uint256 x = LibHalmosExact.abs(c);
        return x >= 10 ** j && x < 10 ** (j + 1);
    }

    /// NEG, split by |c|'s digit count, one j per path. Every nonzero
    /// |c| <= 2^223 < 10^68 has one j in [0, 67], and -c has the same. The
    /// slices take j in [0, 16], [17, 33], [34, 50] and [51, 67].
    function maximizeNegates(int256 c, int32 e, uint256 jBits, uint256 lo, uint256 hi) internal view {
        uint256 j = LibHalmosExact.concrete(jBits, 7);
        if (j < lo || j > hi) return;
        if (c == 0 || c > 2 ** 223 || c < -(2 ** 223)) return;
        if (!hasDigits(c, j)) return;
        if (!LibHalmosExact.maximizeHints(c, j) || !LibHalmosExact.maximizeHints(-c, j)) return;
        (int256 m, int256 me, int256 ms) = this.maximize(c, e);
        (int256 n, int256 ne, int256 ns) = this.maximize(-c, e);
        assert(n == -m && ne == me && ns == ms);
    }

    function check_maximizeNegates0(int256 c, int32 e, uint256 jBits) external view {
        maximizeNegates(c, e, jBits, 0, 16);
    }

    function check_maximizeNegates17(int256 c, int32 e, uint256 jBits) external view {
        maximizeNegates(c, e, jBits, 17, 33);
    }

    function check_maximizeNegates34(int256 c, int32 e, uint256 jBits) external view {
        maximizeNegates(c, e, jBits, 34, 50);
    }

    function check_maximizeNegates51(int256 c, int32 e, uint256 jBits) external view {
        maximizeNegates(c, e, jBits, 51, 67);
    }

    function isMaximized(int256 m) internal pure returns (bool) {
        uint256 x = LibHalmosExact.abs(m);
        return m != type(int256).min && x > T10 && x <= 10 * T10;
    }

    /// Maximized per MAX, with the hints `Impl.add` needs on m and -m.
    function admissible(int256 m) internal pure returns (bool) {
        return isMaximized(m) && m % 1e8 == 0 && LibHalmosExact.divHint(m, 1e75)
            && LibHalmosExact.divHint(-m, 1e75);
    }

    /// X = a at eA = eB + d and Y = b at eB, or the other way round with
    /// `swap`: `minus` of `Impl.add(X, Y)` equals `minus` of
    /// `Impl.add(-Y, -X)`, each taken only when negative.
    function symAt(int256 a, int256 b, int256 eB, int256 eA, bool swap) internal view {
        (int256 cx, int256 ex, int256 cy, int256 ey) = swap ? (b, eB, a, eA) : (a, eA, b, eB);
        try this.implAdd(cx, ex, cy, ey) returns (int256 c1, int256 e1) {
            try this.implAdd(-cy, ey, -cx, ex) returns (int256 c2, int256 e2) {
                (c1, e1) = spread(c1, e1);
                (c2, e2) = spread(c2, e2);
                assert(c1 == c2 && e1 == e2);
            } catch {
                assert(false);
            }
        } catch {
            assert(false);
        }
    }

    /// SYMNEAR on gaps [lo, hi], one D per path. B = 10 yb as in NEAR: by MAX
    /// 10^8 | B for every maximized B, so |yb| <= T10 drops none.
    function symNear(int256 a, int256 yb, int256 eB, uint256 dBits, bool swap, uint256 lo, uint256 hi)
        internal
        view
    {
        uint256 d = LibHalmosExact.concrete(dBits, 7);
        if (d < lo || d > hi) return;
        // forge-lint: disable-next-line(unsafe-typecast)
        if (yb < -int256(T10) || yb > int256(T10)) return;
        int256 b = yb * 10;
        if (!admissible(a) || !admissible(b)) return;
        if (eB < FMIN - 76 || eB > FMAX - 8) return;
        // forge-lint: disable-next-line(unsafe-typecast)
        symAt(a, b, eB, eB + int256(d), swap);
    }

    function check_spreadSymNear0(int256 a, int256 yb, int256 eB, uint256 dBits, bool swap) external view {
        symNear(a, yb, eB, dBits, swap, 0, 19);
    }

    function check_spreadSymNear20(int256 a, int256 yb, int256 eB, uint256 dBits, bool swap) external view {
        symNear(a, yb, eB, dBits, swap, 20, 39);
    }

    function check_spreadSymNear40(int256 a, int256 yb, int256 eB, uint256 dBits, bool swap) external view {
        symNear(a, yb, eB, dBits, swap, 40, 59);
    }

    function check_spreadSymNear60(int256 a, int256 yb, int256 eB, uint256 dBits, bool swap) external view {
        symNear(a, yb, eB, dBits, swap, 60, 76);
    }

    /// SYMFAR: gap D in (76, 2^40], past every gap two int32 exponents less
    /// at most 76 can make.
    function check_spreadSymFar(int256 a, int256 b, int256 eB, uint256 d, bool swap) external view {
        if (d <= 76 || d > 2 ** 40) return;
        if (!admissible(a) || !admissible(b)) return;
        if (eB < FMIN - 76 || eB > FMAX - 8) return;
        // forge-lint: disable-next-line(unsafe-typecast)
        symAt(a, b, eB, eB + int256(d), swap);
    }
}

contract AgreeProbeHalmosTest {
    function agree(Float absolute, Float proportional, Float lowest, Float highest) external pure returns (bool) {
        return LibDecimalFloat.agree(absolute, proportional, lowest, highest);
    }

    function check_probeNoRevert(bytes32 a, bytes32 p, bytes32 l, bytes32 h) external view {
        int256 ca = int256(int224(uint224(uint256(a))));
        int256 cp = int256(int224(uint224(uint256(p))));
        if (ca < 0 || cp < 0 || (ca == 0 && cp == 0)) return;
        try this.agree(Float.wrap(a), Float.wrap(p), Float.wrap(l), Float.wrap(h)) returns (bool) {} catch {
            assert(false);
        }
    }

    function check_probeEitherOrder(bytes32 a, bytes32 p, bytes32 l, bytes32 h) external view {
        int256 ca = int256(int224(uint224(uint256(a))));
        int256 cp = int256(int224(uint224(uint256(p))));
        if (ca < 0 || cp < 0 || (ca == 0 && cp == 0)) return;
        bool x = this.agree(Float.wrap(a), Float.wrap(p), Float.wrap(l), Float.wrap(h));
        bool y = this.agree(Float.wrap(a), Float.wrap(p), Float.wrap(h), Float.wrap(l));
        assert(x == y);
    }
}
