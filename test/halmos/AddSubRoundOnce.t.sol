// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {stdError} from "forge-std-1.17.0/src/StdError.sol";
import {AddSubRoundOnceHalmosTest} from "./AddSubRoundOnce.halmos.t.sol";
import {AddSubSkewedExponentUp} from "./AddSubSkewedExponentUp.sol";
import {AddSubSkewedExponent} from "./AddSubSkewedExponent.sol";
import {AddSubSkewedUp} from "./AddSubSkewedUp.sol";
import {AddSubSkewedDown} from "./AddSubSkewedDown.sol";
import {AddSubFlippedSign} from "./AddSubFlippedSign.sol";
import {AddSubSkewedShortfall} from "./AddSubSkewedShortfall.sol";
import {AddSubUnderShifted} from "./AddSubUnderShifted.sol";
import {AddSubReverts} from "./AddSubReverts.sol";
import {AddSubLongReturn} from "./AddSubLongReturn.sol";

/// Forge checks on the scaffolding of `AddSubRoundOnce.halmos.t.sol`. A lemma
/// that returns early on more inputs than its header says passes halmos with
/// every job green, so these hold MAX, IDEM, NEAR and FAR to their domains:
/// each reaches the call it checks at both ends of every range it is stated
/// over and not one past them (`vm.expectCall` counts the nested call). A
/// lemma that asserts less than the header says passes too, the library being
/// correct, so the sensitivity tests run each lemma on the `AddSub*` subjects
/// beside this file, each of which breaks one component of what a lemma
/// asserts and keeps the rest as the library has it, and expect the assertion
/// panic: a lemma that drops a conjunct passes its subject and fails here.
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
    /// domain, and in neither one exponent past either end. The cancelling
    /// pairs (x, -x) at d = 0 are left out: their sum is zero, which
    /// `Impl.add` returns at exponent 0, and the lemma asserts a result
    /// exponent of eB + d or one more, so it reverts on them. NEAR is not in
    /// the CI matrix (#512).
    function testNearTakesTheWholeDomain() external {
        int256[4] memory xs = edges();
        int256[2] memory ebs = [FMIN - 76, FMAX - 8];
        uint256[2] memory ds = [uint256(0), FIRST_FAR_GAP - 1];
        for (uint256 g = 0; g < ds.length; g++) {
            for (uint256 k = 0; k < ebs.length; k++) {
                for (uint256 i = 0; i < xs.length; i++) {
                    for (uint256 j = 0; j < xs.length; j++) {
                        if (cancels(xs[i], xs[j], ds[g])) continue;
                        expectNearAdds(xs[i], xs[j], ebs[k], ds[g], 1);
                    }
                }
                for (uint256 i = 0; i < xs.length; i++) {
                    for (uint256 j = 0; j < xs.length; j++) {
                        if (cancels(xs[i], xs[j], ds[g])) continue;
                        callNear(xs[i], xs[j], ebs[k], ds[g]);
                    }
                }
            }
            expectNearAdds(HIGH_IN, HIGH_IN, FMIN - 77, ds[g], 0);
            callNear(HIGH_IN, HIGH_IN, FMIN - 77, ds[g]);
            expectNearAdds(HIGH_IN, HIGH_IN, FMAX - 7, ds[g], 0);
            callNear(HIGH_IN, HIGH_IN, FMAX - 7, ds[g]);
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

    /// Whether a 10^d + b is zero: only at d = 0, as |a| 10^d > |b| from d = 1.
    function cancels(int256 a, int256 b, uint256 d) internal pure returns (bool) {
        return d == 0 && a == -b;
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
        int256[2] memory ebs = [FMIN - 76, FMAX - 8 - int256(FIRST_FAR_GAP)];
        for (uint256 k = 0; k < ebs.length; k++) {
            for (uint256 i = 0; i < xs.length; i++) {
                for (uint256 j = 0; j < xs.length; j++) {
                    expectFarAdds(xs[i], xs[j], ebs[k], FIRST_FAR_GAP, 1);
                }
            }
        }
        expectFarAdds(HIGH_IN, HIGH_IN, 0, FIRST_FAR_GAP - 1, 0);
        expectFarAdds(HIGH_IN, HIGH_IN, FMIN - 77, FIRST_FAR_GAP, 0);
        expectFarAdds(HIGH_IN, HIGH_IN, ebs[1] + 1, FIRST_FAR_GAP, 0);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 widest = uint256((FMAX - 8) - (FMIN - 76));
        expectFarAdds(HIGH_IN, HIGH_IN, FMIN - 76, widest, 1);
        expectFarAdds(HIGH_IN, HIGH_IN, FMIN - 76, widest + 1, 0);
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

    /// ZERO fails on the returned magnitude off by one alone, on its sign
    /// alone, on its exponent off by one alone and on `Impl.add` reverting,
    /// with the zero in either place.
    function testZeroOperandLemmaFailsOnEachBrokenConjunct() external {
        expectZeroFails(new AddSubSkewedUp());
        expectZeroFails(new AddSubFlippedSign());
        expectZeroFails(new AddSubSkewedExponent());
        expectZeroFails(new AddSubReverts());
    }

    function expectZeroFails(AddSubRoundOnceHalmosTest subject) internal {
        vm.expectRevert(stdError.assertionError);
        subject.check_addZeroOperand(5, 3, -7, true);
        vm.expectRevert(stdError.assertionError);
        subject.check_addZeroOperand(-5, 3, -7, false);
    }

    /// MINUS fails on `Impl.add` reverting alone, on it returning a third
    /// word alone and on its magnitude off by one alone.
    function testMinusLemmaFailsOnEachBrokenConjunct() external {
        expectMinusFails(new AddSubReverts());
        expectMinusFails(new AddSubLongReturn());
        expectMinusFails(new AddSubSkewedUp());
    }

    function expectMinusFails(AddSubRoundOnceHalmosTest subject) internal {
        vm.expectRevert(stdError.assertionError);
        subject.check_subIsAddNegated(-3, 5, 0, 0, 0, 0);
    }

    /// MAX fails on the shortfall off by one alone, on `maximize` reverting,
    /// on the magnitude off by one alone, on the exponent off by one alone
    /// and on a shift one digit short, at the first and the last digit
    /// count.
    function testMaximizeFloatLemmaFailsOnEachBrokenConjunct() external {
        expectMaxFails(new AddSubSkewedShortfall());
        expectMaxFails(new AddSubReverts());
        expectMaxFails(new AddSubSkewedUp());
        expectMaxFails(new AddSubSkewedExponent());
        expectMaxFails(new AddSubUnderShifted());
    }

    function expectMaxFails(AddSubRoundOnceHalmosTest subject) internal {
        vm.expectRevert(stdError.assertionError);
        subject.check_maximizeFloat(1, 0, 0);
        vm.expectRevert(stdError.assertionError);
        // forge-lint: disable-next-line(unsafe-typecast)
        subject.check_maximizeFloat(-int256(TWO_223), 0, 67);
    }

    /// IDEM fails on each returned part off by one alone and on `maximize`
    /// reverting, at both ends of the magnitude range.
    function testIdempotentLemmaFailsOnEachBrokenConjunct() external {
        expectIdemFails(new AddSubSkewedUp());
        expectIdemFails(new AddSubSkewedExponent());
        expectIdemFails(new AddSubSkewedShortfall());
        expectIdemFails(new AddSubReverts());
    }

    function expectIdemFails(AddSubRoundOnceHalmosTest subject) internal {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 t10 = int256(T10);
        vm.expectRevert(stdError.assertionError);
        subject.check_maximizeIdempotent(t10 + 1, 0);
        vm.expectRevert(stdError.assertionError);
        subject.check_maximizeIdempotent(-10 * t10, 0);
    }

    /// NEAR at its first and last gap fails on the result's magnitude one
    /// too high alone, one too low alone, on its sign alone, on its exponent
    /// off by one alone and on `Impl.add` reverting, in both argument orders.
    /// The last conjunct, exact or at least 2^223 / 10 in magnitude, has no
    /// subject: a result small enough to fail it fails the bounds first.
    function testNearLemmaFailsOnEachBrokenConjunct() external {
        expectNearFails(new AddSubSkewedUp());
        expectNearFails(new AddSubSkewedDown());
        expectNearFails(new AddSubFlippedSign());
        expectNearFails(new AddSubSkewedExponent());
        expectNearFails(new AddSubReverts());
    }

    function expectNearFails(AddSubRoundOnceHalmosTest subject) internal {
        uint256[2] memory ds = [uint256(0), FIRST_FAR_GAP - 1];
        for (uint256 g = 0; g < ds.length; g++) {
            vm.expectRevert(stdError.assertionError);
            subject.check_addNear(HIGH_IN, HIGH_IN / 10, 0, ds[g], false);
            vm.expectRevert(stdError.assertionError);
            subject.check_addNear(HIGH_IN, HIGH_IN / 10, 0, ds[g], true);
        }
    }

    /// NEAR's exponent assertion alone: HIGH_IN + HIGH_IN carries, so its
    /// exponent one too high is two past the gap with the bounds intact.
    function testNearLemmaFailsOnACarriedExponentOneTooHigh() external {
        AddSubRoundOnceHalmosTest subject = new AddSubSkewedExponentUp();
        vm.expectRevert(stdError.assertionError);
        subject.check_addNear(HIGH_IN, HIGH_IN / 10, 0, 0, false);
        vm.expectRevert(stdError.assertionError);
        subject.check_addNear(HIGH_IN, HIGH_IN / 10, 0, 0, true);
    }

    /// NEAR's zero assertion alone: a cancelling sum's result one off zero in
    /// either direction.
    function testNearLemmaFailsOnANonzeroCancellingSum() external {
        expectCancelFails(new AddSubSkewedUp());
        expectCancelFails(new AddSubSkewedDown());
    }

    function expectCancelFails(AddSubRoundOnceHalmosTest subject) internal {
        vm.expectRevert(stdError.assertionError);
        subject.check_addNear(HIGH_IN, -HIGH_IN / 10, 0, 0, false);
        vm.expectRevert(stdError.assertionError);
        subject.check_addNear(HIGH_IN, -HIGH_IN / 10, 0, 0, true);
    }

    /// MINUS takes exactly one digit count pair of the 7 bits each: with the
    /// other index right, every ja in [0, 127] and every jb in [0, 127] runs
    /// `Impl.sub` and `Impl.add` on the pair once in all; at a unit, zero and
    /// the largest magnitudes of each operand, both signs.
    function testMinusTakesEveryDigitCountPairOnce() external {
        expectMinusOnce(1, -1, 0, 0);
        expectMinusOnce(-1, 1, 0, 0);
        expectMinusOnce(0, 0, 77, 77);
        expectMinusOnce(type(int256).max, type(int224).min, 76, 67);
        expectMinusOnce(type(int256).min, type(int224).max, 76, 67);
        expectMinusOnce(0, type(int224).min, 77, 67);
        expectMinusOnce(type(int256).max, 0, 76, 77);
    }

    function expectMinusOnce(int256 ca, int224 cb, uint256 ja, uint256 jb) internal {
        vm.expectCall(address(this), abi.encodeCall(this.implSub, (ca, int256(3), int256(cb), int256(-7))), 2);
        vm.expectCall(address(this), abi.encodeCall(this.implAdd, (ca, int256(3), -int256(cb), int256(-7))), 2);
        for (uint256 j = 0; j < 2 ** CASE_BITS; j++) {
            this.check_subIsAddNegated(cb, ca, 3, -7, j, jb);
            this.check_subIsAddNegated(cb, ca, 3, -7, ja, j);
        }
    }

    /// FAR fails on the result's exponent off by one alone, on its sign
    /// alone, on its magnitude off by one alone and on `Impl.add` reverting,
    /// in both argument orders, for operands of equal and of opposite sign.
    function testFarLemmaFailsOnEachBrokenConjunct() external {
        expectFarFails(new AddSubSkewedExponent());
        expectFarFails(new AddSubFlippedSign());
        expectFarFails(new AddSubSkewedUp());
        expectFarFails(new AddSubReverts());
    }

    function expectFarFails(AddSubRoundOnceHalmosTest subject) internal {
        int256[2] memory bs = [HIGH_IN, -HIGH_IN];
        for (uint256 i = 0; i < bs.length; i++) {
            vm.expectRevert(stdError.assertionError);
            subject.check_addFar(HIGH_IN, bs[i], 0, FIRST_FAR_GAP, false);
            vm.expectRevert(stdError.assertionError);
            subject.check_addFar(HIGH_IN, bs[i], 0, FIRST_FAR_GAP, true);
        }
    }
}
