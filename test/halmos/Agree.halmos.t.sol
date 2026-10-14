// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float, LibDecimalFloat} from "../../src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {AgreeToleranceNegative, AgreeNoPositiveTolerance} from "../../src/error/ErrDecimalFloat.sol";
import {LibHalmosExact} from "./LibHalmosExact.sol";

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
/// - MAX, IDEM: for nonzero int224 x at an int32 exponent, `Impl.add` on x
///   takes the same steps as on M(x), the maximized parts, whose exponent is
///   x's less k in [8, 76], so in [int32.min - 76, int32.max - 8].
/// - NEG here: M(-x) is -M(x) at the same exponent and shortfall.
///
/// So for nonzero l, h, with X = M(h) and Y = M(-l) = -M(l), the two spreads
/// are `minus` of `Impl.add(X, Y)` and of `Impl.add(-Y, -X)` when negative.
/// SYMNEAR (exponent gap d in [0, 76]) and SYMFAR (d > 76) prove those equal
/// for every maximized X, Y with X's exponent the larger, over every maximized
/// exponent; two of those are under 2^33 apart. With X's exponent the
/// smaller, the equality is SYMNEAR or SYMFAR on (-Y, -X), which are
/// maximized too, with its two sides exchanged.
///
/// NEG is sliced by |c|'s digit count j into [0, 16], [17, 33], [34, 50] and
/// [51, 67], every nonzero int224's j in one of them. SYMNEAR is one slice
/// per gap, 77 slices covering every d in [0, 76].
///
/// The lemmas return early when a hint filter is false. HINTS here proves
/// `divHints`, `negDivHint` and `overflowHint` true for every input they are
/// given, and `LibHalmosExact.halmos.t.sol` proves `maximizeHints`, so the
/// early returns exclude nothing.
///
/// Not proved: the verdict, `lte` of the spread against `max(absolute,
/// Impl.mul(proportional, anchor))`; halmos leaves `Impl.mul`'s 512-bit
/// product uninterpreted.
contract AgreeHalmosTest {
    /// floor(int256.max / 10).
    uint256 internal constant T10 = uint256(type(int256).max) / 10;
    int256 internal constant FMIN = type(int32).min;
    int256 internal constant FMAX = type(int32).max;
    int256 internal constant E75 = 1e75;

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
        (bool ok, bytes memory out) = address(this)
            .staticcall(abi.encodeCall(this.agree, (Float.wrap(a), Float.wrap(p), Float.wrap(l), Float.wrap(h))));
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
        // forge-lint: disable-next-line(unsafe-typecast)
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

    /// HINTS: the hint predicates hold for every input they are given.
    function check_divHintsHold(int256 m) external pure {
        assert(divHints(m));
    }

    /// y is any int256 but int256.min and s = 10^d for d in [0, 76], one d per
    /// path; `symNear` gives it B = 10 yb with |yb| <= T10.
    function check_negDivHintHolds(int256 y, uint256 dBits) external pure {
        uint256 d = LibHalmosExact.concrete(dBits, 7);
        if (d > 76 || y == type(int256).min) return;
        // forge-lint: disable-next-line(unsafe-typecast)
        assert(negDivHint(y, int256(10 ** d)));
    }

    function check_overflowHintHolds(int256 c) external pure {
        assert(overflowHint(c));
    }

    /// Every predicate below is branchless, so a filter adds no paths.
    /// Maximized per MAX: T10 < |m| <= 10 T10 and 10^8 | m.
    function maximized(int256 m) internal pure returns (bool r) {
        uint256 t10 = T10;
        assembly ("memory-safe") {
            let s := sar(255, m)
            let x := sub(xor(m, s), s)
            r := and(and(gt(x, t10), iszero(gt(x, mul(10, t10)))), iszero(smod(m, 100000000)))
        }
    }

    /// `divHint` on m and -m, branchless: the facts `Impl.maximize` needs to
    /// return a maximized m or -m unchanged. True for every int256 m.
    function divHints(int256 m) internal pure returns (bool r) {
        assembly ("memory-safe") {
            let s := sar(255, m)
            let x := sub(xor(m, s), s)
            let small := lt(x, E75)
            r := and(eq(iszero(sdiv(m, E75)), small), eq(iszero(sdiv(sub(0, m), E75)), small))
        }
    }

    function admissible(int256 m) internal pure returns (bool r) {
        r = maximized(m);
        bool h = divHints(m);
        assembly ("memory-safe") {
            r := and(r, h)
        }
    }

    /// For y != int256.min and s > 0: `sdiv` and `smod` are odd in y.
    function negDivHint(int256 y, int256 s) internal pure returns (bool r) {
        assembly ("memory-safe") {
            let n := sub(0, y)
            r := and(eq(sdiv(n, s), sub(0, sdiv(y, s))), eq(smod(n, s), sub(0, smod(y, s))))
        }
    }

    /// For c < 0, a positive sum s = uint256(c) past int256.max: `Impl.add`
    /// sheds it as uint256(c) / 10, and sheds the negative sum -s, wrapped to
    /// -c, as (uint256(-c) + 3) / 10 - (2^256 - 1) / 10. With N = 2^256 and
    /// N mod 10 = 6, the latter is (N - 6) / 10 + floor((9 - s) / 10) -
    /// (N - 6) / 10 = -floor(s / 10). True for every c.
    function overflowHint(int256 c) internal pure returns (bool r) {
        uint256 maxTenth = type(uint256).max / 10;
        assembly ("memory-safe") {
            r := or(iszero(slt(c, 0)), eq(sub(div(add(sub(0, c), 3), 10), maxTenth), sub(0, div(c, 10))))
        }
    }

    /// The hints for the sums `Impl.add` forms from a and b / 10^d, with or
    /// without its one unit cancellation bump, in either sign.
    function sumHints(int256 a, int256 b, int256 s) internal pure returns (bool r) {
        r = negDivHint(b, s);
        int256 q;
        assembly ("memory-safe") {
            q := sdiv(b, s)
        }
        unchecked {
            int256 c = a + q;
            r = and3(r, overflowHint(c - 1), overflowHint(1 - c));
            r = and3(r, overflowHint(c), overflowHint(-c));
            r = and3(r, overflowHint(c + 1), overflowHint(-1 - c));
        }
    }

    function and3(bool x, bool y, bool z) internal pure returns (bool r) {
        assembly ("memory-safe") {
            r := and(x, and(y, z))
        }
    }

    /// X = a at eA >= eB and Y = b at eB: `minus` of `Impl.add(X, Y)` equals
    /// `minus` of `Impl.add(-Y, -X)`, each taken only when negative.
    function symAt(int256 a, int256 b, int256 eB, int256 eA) internal view {
        (int256 cx, int256 ex, int256 cy, int256 ey) = (a, eA, b, eB);
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

    /// SYMNEAR at gap d, one slice per d in [0, 76]. B = 10 yb as in NEAR: by
    /// MAX 10^8 | B for every maximized B, so |yb| <= T10 drops none.
    function symNear(int256 a, int256 yb, int256 eB, uint256 d) internal view {
        // forge-lint: disable-next-line(unsafe-typecast)
        if (yb < -int256(T10) || yb > int256(T10)) return;
        int256 b = yb * 10;
        if (!admissible(a) || !admissible(b)) return;
        // forge-lint: disable-next-line(unsafe-typecast)
        if (!sumHints(a, b, int256(10 ** d))) return;
        if (eB < FMIN - 76 || eB > FMAX - 8) return;
        // forge-lint: disable-next-line(unsafe-typecast)
        symAt(a, b, eB, eB + int256(d));
    }

    function check_spreadSymNear00(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 0);
    }

    function check_spreadSymNear01(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 1);
    }

    function check_spreadSymNear02(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 2);
    }

    function check_spreadSymNear03(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 3);
    }

    function check_spreadSymNear04(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 4);
    }

    function check_spreadSymNear05(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 5);
    }

    function check_spreadSymNear06(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 6);
    }

    function check_spreadSymNear07(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 7);
    }

    function check_spreadSymNear08(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 8);
    }

    function check_spreadSymNear09(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 9);
    }

    function check_spreadSymNear10(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 10);
    }

    function check_spreadSymNear11(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 11);
    }

    function check_spreadSymNear12(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 12);
    }

    function check_spreadSymNear13(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 13);
    }

    function check_spreadSymNear14(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 14);
    }

    function check_spreadSymNear15(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 15);
    }

    function check_spreadSymNear16(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 16);
    }

    function check_spreadSymNear17(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 17);
    }

    function check_spreadSymNear18(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 18);
    }

    function check_spreadSymNear19(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 19);
    }

    function check_spreadSymNear20(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 20);
    }

    function check_spreadSymNear21(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 21);
    }

    function check_spreadSymNear22(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 22);
    }

    function check_spreadSymNear23(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 23);
    }

    function check_spreadSymNear24(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 24);
    }

    function check_spreadSymNear25(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 25);
    }

    function check_spreadSymNear26(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 26);
    }

    function check_spreadSymNear27(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 27);
    }

    function check_spreadSymNear28(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 28);
    }

    function check_spreadSymNear29(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 29);
    }

    function check_spreadSymNear30(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 30);
    }

    function check_spreadSymNear31(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 31);
    }

    function check_spreadSymNear32(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 32);
    }

    function check_spreadSymNear33(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 33);
    }

    function check_spreadSymNear34(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 34);
    }

    function check_spreadSymNear35(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 35);
    }

    function check_spreadSymNear36(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 36);
    }

    function check_spreadSymNear37(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 37);
    }

    function check_spreadSymNear38(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 38);
    }

    function check_spreadSymNear39(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 39);
    }

    function check_spreadSymNear40(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 40);
    }

    function check_spreadSymNear41(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 41);
    }

    function check_spreadSymNear42(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 42);
    }

    function check_spreadSymNear43(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 43);
    }

    function check_spreadSymNear44(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 44);
    }

    function check_spreadSymNear45(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 45);
    }

    function check_spreadSymNear46(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 46);
    }

    function check_spreadSymNear47(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 47);
    }

    function check_spreadSymNear48(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 48);
    }

    function check_spreadSymNear49(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 49);
    }

    function check_spreadSymNear50(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 50);
    }

    function check_spreadSymNear51(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 51);
    }

    function check_spreadSymNear52(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 52);
    }

    function check_spreadSymNear53(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 53);
    }

    function check_spreadSymNear54(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 54);
    }

    function check_spreadSymNear55(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 55);
    }

    function check_spreadSymNear56(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 56);
    }

    function check_spreadSymNear57(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 57);
    }

    function check_spreadSymNear58(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 58);
    }

    function check_spreadSymNear59(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 59);
    }

    function check_spreadSymNear60(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 60);
    }

    function check_spreadSymNear61(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 61);
    }

    function check_spreadSymNear62(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 62);
    }

    function check_spreadSymNear63(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 63);
    }

    function check_spreadSymNear64(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 64);
    }

    function check_spreadSymNear65(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 65);
    }

    function check_spreadSymNear66(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 66);
    }

    function check_spreadSymNear67(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 67);
    }

    function check_spreadSymNear68(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 68);
    }

    function check_spreadSymNear69(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 69);
    }

    function check_spreadSymNear70(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 70);
    }

    function check_spreadSymNear71(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 71);
    }

    function check_spreadSymNear72(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 72);
    }

    function check_spreadSymNear73(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 73);
    }

    function check_spreadSymNear74(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 74);
    }

    function check_spreadSymNear75(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 75);
    }

    function check_spreadSymNear76(int256 a, int256 yb, int256 eB) external view {
        symNear(a, yb, eB, 76);
    }

    /// SYMFAR: gap d in (76, 2^40], past every gap two maximized exponents
    /// can make.
    function check_spreadSymFar(int256 a, int256 b, int256 eB, uint256 d) external view {
        if (d <= 76 || d > 2 ** 40) return;
        if (!admissible(a) || !admissible(b)) return;
        if (eB < FMIN - 76 || eB > FMAX - 8) return;
        // forge-lint: disable-next-line(unsafe-typecast)
        symAt(a, b, eB, eB + int256(d));
    }
}
