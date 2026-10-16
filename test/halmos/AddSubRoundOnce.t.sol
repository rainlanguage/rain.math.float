// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {AddSubRoundOnceHalmosTest} from "./AddSubRoundOnce.halmos.t.sol";

/// Forge checks on the scaffolding of `AddSubRoundOnce.halmos.t.sol`. A lemma
/// that returns early on more inputs than its header says passes halmos with
/// every job green, so these hold ZERO, MINUS, MAX, IDEM, NEAR and FAR to
/// their domains: each reaches the call it checks at both ends of every range
/// it is stated over and not one past them (`vm.expectCall` counts the nested
/// call). A lemma whose assertion is weakened passes halmos too, so each
/// `AddSubRoundOnce*Test` harness overrides one wrapper to return a result
/// wrong in one way and checks the lemma rejects it.
contract AddSubRoundOnceCoverTest is Test, AddSubRoundOnceHalmosTest {
    /// The largest maximized magnitude, the last multiple of 10^8 at most
    /// 10 T10, and the smallest, the first above T10.
    // forge-lint: disable-next-line(unsafe-typecast, divide-before-multiply)
    int256 internal constant HIGH_IN = int256(10 * T10 / 1e8 * 1e8);
    // forge-lint: disable-next-line(unsafe-typecast, divide-before-multiply)
    int256 internal constant LOW_IN = int256((T10 / 1e8 + 1) * 1e8);
    /// NEAR stops at gap 76 and FAR starts at 77.
    uint256 internal constant FIRST_FAR_GAP = 77;
    /// The 7 bits MAX and NEAR split their case index from.
    uint256 internal constant CASE_BITS = 7;
    /// The ends of NEAR's and FAR's exponent domain, from int32 itself: the
    /// lemmas bound it with their own FMIN and FMAX, which are under test.
    int256 internal constant LOWEST_EB = int256(type(int32).min) - 76;
    int256 internal constant HIGHEST_EB = int256(type(int32).max) - 8;

    /// Both maximized magnitudes in both signs: the operands at the edges of
    /// NEAR's and FAR's domain, closed under negation.
    function edges() internal pure returns (int256[4] memory) {
        return [HIGH_IN, -HIGH_IN, LOW_IN, -LOW_IN];
    }

    /// MAX: both ends of every digit count class of [-2^223, 2^223], in both
    /// signs, reach `maximize` in exactly one of the cases the 7 bits give,
    /// and the magnitudes one past 2^223 in none.
    function testMaximizeFloatTakesEveryDigitCount() external {
        for (uint256 j = 0; j <= 67; j++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 low = int256(10 ** j);
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 high = j < 67 ? low * 10 - 1 : int256(TWO_223);
            expectMaximizedOnce(low, 1);
            expectMaximizedOnce(high, 1);
            expectMaximizedOnce(-low, 1);
            expectMaximizedOnce(-high, 1);
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        expectMaximizedOnce(int256(TWO_223) + 1, 0);
        // forge-lint: disable-next-line(unsafe-typecast)
        expectMaximizedOnce(-int256(TWO_223) - 1, 0);
    }

    /// Over every case index, `check_maximizeFloat` runs `maximize` on c
    /// `count` times.
    function expectMaximizedOnce(int256 c, uint64 count) internal {
        vm.expectCall(address(this), abi.encodeCall(this.maximize, (c, int256(0))), count);
        for (uint256 j = 0; j < 2 ** CASE_BITS; j++) {
            this.check_maximizeFloat(c, 0, j);
        }
    }

    /// MAX at c = floor(T10 / 1e9), whose maximized form c 10^10 is the one
    /// in [-2^223, 2^223] with |c| = floor(10 T10 / 10^k): the magnitude
    /// check's upper bound is closed there.
    function testMaximizeFloatAtTheTimesTenBound() external {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 c = int256(T10 / 1e9);
        vm.expectCall(address(this), abi.encodeCall(this.maximize, (c, int256(0))), 1);
        this.check_maximizeFloat(c, 0, 66);
    }

    /// IDEM reaches `maximize` at both ends of MAX's magnitude range, both
    /// signs, and not one past either end.
    function testIdempotentTakesBothEndsAndSigns() external {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 t10 = int256(T10);
        int256[4] memory ins = [t10 + 1, 10 * t10, -(t10 + 1), -10 * t10];
        int256[4] memory outs = [t10, 10 * t10 + 1, -t10, -(10 * t10 + 1)];
        for (uint256 i = 0; i < ins.length; i++) {
            vm.expectCall(address(this), abi.encodeCall(this.maximize, (ins[i], int256(0))), 1);
            this.check_maximizeIdempotent(ins[i], 0);
            vm.expectCall(address(this), abi.encodeCall(this.maximize, (outs[i], int256(0))), 0);
            this.check_maximizeIdempotent(outs[i], 0);
        }
    }

    /// NEAR takes exactly the gaps in [0, 76] of the 7 bits: each reaches
    /// `Impl.add` in both argument orders at HIGH_IN and HIGH_IN, and no gap
    /// from 77 does.
    function testNearTakesEveryGapToSeventySix() external {
        for (uint256 d = 0; d < 2 ** CASE_BITS; d++) {
            expectNearAdds(HIGH_IN, HIGH_IN, 0, d, d < FIRST_FAR_GAP ? 1 : 0);
            callNear(HIGH_IN, HIGH_IN, 0, d);
        }
    }

    /// NEAR at its first and last gap reaches `Impl.add` in both argument
    /// orders on every pair of edge operands at both ends of the exponent
    /// domain, cancelling pairs (x, -x) at d = 0 included, and in neither one
    /// exponent past either end. NEAR is not in the CI matrix (#512).
    function testNearTakesTheWholeDomain() external {
        int256[4] memory xs = edges();
        int256[2] memory ebs = [LOWEST_EB, HIGHEST_EB];
        uint256[2] memory ds = [uint256(0), FIRST_FAR_GAP - 1];
        for (uint256 g = 0; g < ds.length; g++) {
            for (uint256 k = 0; k < ebs.length; k++) {
                for (uint256 i = 0; i < xs.length; i++) {
                    for (uint256 j = 0; j < xs.length; j++) {
                        expectNearAdds(xs[i], xs[j], ebs[k], ds[g], 1);
                    }
                }
                for (uint256 i = 0; i < xs.length; i++) {
                    for (uint256 j = 0; j < xs.length; j++) {
                        callNear(xs[i], xs[j], ebs[k], ds[g]);
                    }
                }
            }
            expectNearAdds(HIGH_IN, HIGH_IN, LOWEST_EB - 1, ds[g], 0);
            callNear(HIGH_IN, HIGH_IN, LOWEST_EB - 1, ds[g]);
            expectNearAdds(HIGH_IN, HIGH_IN, HIGHEST_EB + 1, ds[g], 0);
            callNear(HIGH_IN, HIGH_IN, HIGHEST_EB + 1, ds[g]);
        }
    }

    /// Each order's add from `check_addNear(a, b / 10, eB, d, swap)` over
    /// both values of swap, `count` times. At d = 0 the swapped add has the
    /// calldata of the unswapped add of the pair (b, a), which `edges` also
    /// holds, so the one expectation stands for both: a call is counted only
    /// by the expectations before it, so a block's pairs are all expected
    /// before any is called.
    function expectNearAdds(int256 a, int256 b, int256 eB, uint256 d, uint64 count) internal {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 eA = eB + int256(d);
        if (d == 0) {
            vm.expectCall(address(this), abi.encodeCall(this.implAdd, (a, eA, b, eB)), 2 * count);
        } else {
            vm.expectCall(address(this), abi.encodeCall(this.implAdd, (a, eA, b, eB)), count);
            vm.expectCall(address(this), abi.encodeCall(this.implAdd, (b, eB, a, eA)), count);
        }
    }

    function callNear(int256 a, int256 b, int256 eB, uint256 d) internal view {
        this.check_addNear(a, b / 10, eB, d, false);
        this.check_addNear(a, b / 10, eB, d, true);
    }

    /// NEAR on opposite-sign edge operands at every gap, both argument orders:
    /// `checkSum`'s cancelling arm at gaps 1 to 75 too.
    function testNearOpposingSignsEveryGap() external view {
        for (uint256 d = 0; d < FIRST_FAR_GAP; d++) {
            callNear(HIGH_IN, -LOW_IN, 0, d);
            callNear(-LOW_IN, HIGH_IN, 0, d);
            callNear(LOW_IN, -HIGH_IN, 0, d);
            callNear(-HIGH_IN, LOW_IN, 0, d);
        }
    }

    /// NEAR on a cancelling pair at gap 0: `Impl.add` returns the maximized
    /// zero (0, 0), so the lemma takes `checkSum`'s zero path and asserts
    /// nothing about the exponent. rain-marvin's counterexample to the form
    /// that asserted an exponent of eB or eB + 1 first.
    function testNearZeroSum() external view {
        this.check_addNear(1e76, -1e75, 5, 0, false);
        this.check_addNear(-1e76, 1e75, -7, 0, true);
    }

    /// FAR takes exactly the gaps from 77 that keep both exponents in the
    /// maximized range: at its first gap it reaches `Impl.add` in both
    /// argument orders on every pair of edge operands with eB at both ends of
    /// its domain, and in neither at gap 76 or one exponent past either end;
    /// the widest gap, from the lowest eB to the highest eA, is in and one
    /// wider is out.
    function testFarTakesTheWholeDomain() external {
        int256[4] memory xs = edges();
        // forge-lint: disable-next-line(unsafe-typecast)
        int256[2] memory ebs = [LOWEST_EB, HIGHEST_EB - int256(FIRST_FAR_GAP)];
        for (uint256 k = 0; k < ebs.length; k++) {
            for (uint256 i = 0; i < xs.length; i++) {
                for (uint256 j = 0; j < xs.length; j++) {
                    expectFarAdds(xs[i], xs[j], ebs[k], FIRST_FAR_GAP, 1);
                }
            }
        }
        expectFarAdds(HIGH_IN, HIGH_IN, 0, FIRST_FAR_GAP - 1, 0);
        expectFarAdds(HIGH_IN, HIGH_IN, LOWEST_EB - 1, FIRST_FAR_GAP, 0);
        expectFarAdds(HIGH_IN, HIGH_IN, ebs[1] + 1, FIRST_FAR_GAP, 0);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 widest = uint256(HIGHEST_EB - LOWEST_EB);
        expectFarAdds(HIGH_IN, HIGH_IN, LOWEST_EB, widest, 1);
        expectFarAdds(HIGH_IN, HIGH_IN, LOWEST_EB, widest + 1, 0);
    }

    /// `check_addFar(a, b, eB, d, swap)` for both values of swap makes each
    /// order's add `count` times.
    function expectFarAdds(int256 a, int256 b, int256 eB, uint256 d, uint64 count) internal {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 eA = eB + int256(d);
        vm.expectCall(address(this), abi.encodeCall(this.implAdd, (a, eA, b, eB)), count);
        vm.expectCall(address(this), abi.encodeCall(this.implAdd, (b, eB, a, eA)), count);
        this.check_addFar(a, b, eB, d, false);
        this.check_addFar(a, b, eB, d, true);
    }

    /// ZERO reaches `Impl.add` with the zero operand in each position, for
    /// zero and both int224 and int256 ends of c, with both exponents at
    /// either end of int32. Zero takes one exponent order: with c zero the
    /// two orders of the other have the same calldata.
    function testZeroOperandTakesBothPositions() external {
        int256[6] memory cs = [int256(1), -1, 2 ** 223 - 1, -(2 ** 223), type(int256).max, type(int256).min];
        expectZeroAdds(0, FMIN, FMAX);
        for (uint256 i = 0; i < cs.length; i++) {
            expectZeroAdds(cs[i], FMIN, FMAX);
            expectZeroAdds(cs[i], FMAX, FMIN);
        }
    }

    /// `check_addZeroOperand(c, e, ez, zeroFirst)` over both values of
    /// zeroFirst adds (0, ez) to (c, e) once in each order.
    function expectZeroAdds(int256 c, int256 e, int256 ez) internal {
        vm.expectCall(address(this), abi.encodeCall(this.implAdd, (int256(0), ez, c, e)), 1);
        vm.expectCall(address(this), abi.encodeCall(this.implAdd, (c, e, int256(0), ez)), 1);
        this.check_addZeroOperand(c, e, ez, true);
        this.check_addZeroOperand(c, e, ez, false);
    }

    /// MINUS, cb zero: over the whole 2^7 x 2^7 case grid, every ca at zero,
    /// one and both int256 ends reaches `Impl.sub` and the negated `Impl.add`
    /// exactly once. Zero is digit count 77 for both operands, the last case
    /// index MINUS admits; MINUS is not in the CI matrix (#513).
    function testSubIsAddNegatedTakesZeroB() external {
        expectSubOnceForEveryA(0);
    }

    /// MINUS, cb at int224.max.
    function testSubIsAddNegatedTakesMaxB() external {
        expectSubOnceForEveryA(type(int224).max);
    }

    /// MINUS, cb at int224.min: -cb is 2^223, one above int224.max.
    function testSubIsAddNegatedTakesMinB() external {
        expectSubOnceForEveryA(type(int224).min);
    }

    function expectSubOnceForEveryA(int224 cb) internal {
        int256[4] memory cas = [int256(0), 1, type(int256).max, type(int256).min];
        for (uint256 a = 0; a < cas.length; a++) {
            vm.expectCall(address(this), abi.encodeCall(this.implSub, (cas[a], int256(0), int256(cb), int256(0))), 1);
            vm.expectCall(address(this), abi.encodeCall(this.implAdd, (cas[a], int256(0), -int256(cb), int256(0))), 1);
        }
        for (uint256 a = 0; a < cas.length; a++) {
            for (uint256 ja = 0; ja < 2 ** CASE_BITS; ja++) {
                for (uint256 jb = 0; jb < 2 ** CASE_BITS; jb++) {
                    this.check_subIsAddNegated(cb, cas[a], 0, 0, ja, jb);
                }
            }
        }
    }
}
