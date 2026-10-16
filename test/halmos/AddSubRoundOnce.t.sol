// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {AddSubRoundOnceHalmosTest} from "./AddSubRoundOnce.halmos.t.sol";

/// Forge checks on the scaffolding of `AddSubRoundOnce.halmos.t.sol`. A lemma
/// that returns early on more inputs than its header says passes halmos with
/// every job green, so these hold ZERO, MINUS, MAX, IDEM, NEAR and FAR to
/// their domains: each reaches the call it checks at both ends of every range
/// it is stated over and not one past them (`vm.expectCall` counts the nested
/// call). A lemma whose assertion is weakened passes halmos too, so the
/// harness contracts below each override one wrapper to return a result wrong
/// in one way and check the lemma rejects it.
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
        int256[2] memory ebs = [FMIN - 76, FMAX - 8];
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

/// `maximize` one shift short: the result is exact and still c 10^k, but
/// |c 10^k| is at most T10.
contract AddSubRoundOnceMaximizeShortShiftTest is Test, AddSubRoundOnceHalmosTest {
    function maximize(int256 c, int256 e) external pure override returns (int256, int256, int256) {
        (int256 m, int256 me,) = LibDecimalFloatImplementation.maximize(c, e);
        return (m / 10, me + 1, 0);
    }

    /// MAX at c = floor(T10 / 1e9): the short form c 10^9 has |c| equal to
    /// floor(T10 / 10^9), so only the strict lower bound of the magnitude
    /// check rejects it.
    function testMaxRejectsAMagnitudeAtT10() external {
        vm.expectRevert(stdError.assertionError);
        // forge-lint: disable-next-line(unsafe-typecast)
        this.check_maximizeFloat(int256(T10 / 1e9), 0, 66);
    }
}

/// `maximize` with the coefficient one above the exact product.
contract AddSubRoundOnceMaximizeOffByOneTest is Test, AddSubRoundOnceHalmosTest {
    function maximize(int256 c, int256 e) external pure override returns (int256, int256, int256) {
        (int256 m, int256 me,) = LibDecimalFloatImplementation.maximize(c, e);
        return (m + 1, me, 0);
    }

    /// MAX: m must be c 10^k exactly; the shift and the magnitude bounds
    /// still hold for 10^76 + 1.
    function testMaxRejectsAnInexactProduct() external {
        vm.expectRevert(stdError.assertionError);
        this.check_maximizeFloat(1, 0, 0);
    }

    /// IDEM: a maximized coefficient must come back unchanged.
    function testIdemRejectsAChangedCoefficient() external {
        vm.expectRevert(stdError.assertionError);
        this.check_maximizeIdempotent(1e76, 0);
    }
}

/// `maximize` with the exponent one above.
contract AddSubRoundOnceMaximizeExponentAboveTest is Test, AddSubRoundOnceHalmosTest {
    function maximize(int256 c, int256 e) external pure override returns (int256, int256, int256) {
        (int256 m, int256 me,) = LibDecimalFloatImplementation.maximize(c, e);
        return (m, me + 1, 0);
    }

    /// IDEM: the exponent must come back unchanged.
    function testIdemRejectsAChangedExponent() external {
        vm.expectRevert(stdError.assertionError);
        this.check_maximizeIdempotent(1e76, 0);
    }
}

/// `maximize` reporting a shortfall of one.
contract AddSubRoundOnceMaximizeShortfallTest is Test, AddSubRoundOnceHalmosTest {
    function maximize(int256 c, int256 e) external pure override returns (int256, int256, int256) {
        (int256 m, int256 me,) = LibDecimalFloatImplementation.maximize(c, e);
        return (m, me, 1);
    }

    /// MAX: no shortfall for an int32 exponent.
    function testMaxRejectsAShortfall() external {
        vm.expectRevert(stdError.assertionError);
        this.check_maximizeFloat(1, 0, 0);
    }

    /// IDEM: no shortfall for a maximized input.
    function testIdemRejectsAShortfall() external {
        vm.expectRevert(stdError.assertionError);
        this.check_maximizeIdempotent(1e76, 0);
    }
}

/// `Impl.add` with the coefficient one above. The NEAR pair is a = b = 1e76
/// at gap 5, whose exact sum 1e76 + 1e71 at eA is the result; the FAR pair
/// is the same operands at gap 77, where the result is A.
contract AddSubRoundOnceAddCoefficientAboveTest is Test, AddSubRoundOnceHalmosTest {
    function implAdd(int256 ca, int256 ea, int256 cb, int256 eb) external pure override returns (int256, int256) {
        (int256 c, int256 e) = LibDecimalFloatImplementation.add(ca, ea, cb, eb);
        return (c + 1, e);
    }

    /// ZERO: the other operand's coefficient must come back unchanged.
    function testZeroRejectsAChangedCoefficient() external {
        vm.expectRevert(stdError.assertionError);
        this.check_addZeroOperand(5, 3, -2, true);
    }

    /// NEAR: |c| 10^t must not exceed |S|.
    function testNearRejectsAResultAboveTheSum() external {
        vm.expectRevert(stdError.assertionError);
        this.check_addNear(1e76, 1e75, 0, 5, false);
    }

    /// FAR: the magnitude is |A| when the signs agree.
    function testFarRejectsAChangedMagnitude() external {
        vm.expectRevert(stdError.assertionError);
        this.check_addFar(1e76, 1e76, 0, 77, false);
    }
}

/// `Impl.add` with the coefficient one below.
contract AddSubRoundOnceAddCoefficientBelowTest is Test, AddSubRoundOnceHalmosTest {
    function implAdd(int256 ca, int256 ea, int256 cb, int256 eb) external pure override returns (int256, int256) {
        (int256 c, int256 e) = LibDecimalFloatImplementation.add(ca, ea, cb, eb);
        return (c - 1, e);
    }

    /// NEAR: |S| must be below (|c| + 1) 10^t.
    function testNearRejectsAResultTooFarBelowTheSum() external {
        vm.expectRevert(stdError.assertionError);
        this.check_addNear(1e76, 1e75, 0, 5, false);
    }
}

/// `Impl.add` with the exponent one above.
contract AddSubRoundOnceAddExponentAboveTest is Test, AddSubRoundOnceHalmosTest {
    function implAdd(int256 ca, int256 ea, int256 cb, int256 eb) external pure override returns (int256, int256) {
        (int256 c, int256 e) = LibDecimalFloatImplementation.add(ca, ea, cb, eb);
        return (c, e + 1);
    }

    /// ZERO: the other operand's exponent must come back unchanged.
    function testZeroRejectsAChangedExponent() external {
        vm.expectRevert(stdError.assertionError);
        this.check_addZeroOperand(5, 3, -2, false);
    }

    /// FAR: the result exponent is eA.
    function testFarRejectsAChangedExponent() external {
        vm.expectRevert(stdError.assertionError);
        this.check_addFar(1e76, 1e76, 0, 77, false);
    }
}

/// `Impl.add` with the coefficient negated.
contract AddSubRoundOnceAddNegatedTest is Test, AddSubRoundOnceHalmosTest {
    function implAdd(int256 ca, int256 ea, int256 cb, int256 eb) external pure override returns (int256, int256) {
        (int256 c, int256 e) = LibDecimalFloatImplementation.add(ca, ea, cb, eb);
        return (-c, e);
    }

    /// NEAR: c has S's sign.
    function testNearRejectsAWrongSign() external {
        vm.expectRevert(stdError.assertionError);
        this.check_addNear(1e76, 1e75, 0, 5, false);
    }

    /// FAR: c has A's sign.
    function testFarRejectsAWrongSign() external {
        vm.expectRevert(stdError.assertionError);
        this.check_addFar(1e76, 1e76, 0, 77, false);
    }
}

/// `Impl.sub` reverting with the bytes the negated `Impl.add` returns: the
/// two outcomes differ only in the success flag.
contract AddSubRoundOnceSubRevertsWithAddBytesTest is Test, AddSubRoundOnceHalmosTest {
    function implSub(int256 ca, int256 ea, int256 cb, int256 eb) external pure override returns (int256, int256) {
        (int256 c, int256 e) = LibDecimalFloatImplementation.add(ca, ea, -cb, eb);
        bytes memory data = abi.encode(c, e);
        assembly ("memory-safe") {
            revert(add(data, 0x20), mload(data))
        }
    }

    /// MINUS: sub and add succeed or revert together.
    function testMinusRejectsADifferentOutcome() external {
        vm.expectRevert(stdError.assertionError);
        this.check_subIsAddNegated(1, 1, 0, 0, 0, 0);
    }
}

/// `Impl.sub` returning only the coefficient word, a prefix of what the
/// negated `Impl.add` returns.
contract AddSubRoundOnceSubTruncatedTest is Test, AddSubRoundOnceHalmosTest {
    function implSub(int256 ca, int256 ea, int256 cb, int256 eb) external pure override returns (int256, int256) {
        (int256 c,) = LibDecimalFloatImplementation.add(ca, ea, -cb, eb);
        assembly ("memory-safe") {
            mstore(0, c)
            return(0, 0x20)
        }
    }

    /// MINUS: the two outputs have the same length.
    function testMinusRejectsAShorterEncoding() external {
        vm.expectRevert(stdError.assertionError);
        this.check_subIsAddNegated(1, 1, 0, 0, 0, 0);
    }
}

/// `Impl.sub` with the coefficient one above the negated `Impl.add`'s.
contract AddSubRoundOnceSubCoefficientAboveTest is Test, AddSubRoundOnceHalmosTest {
    function implSub(int256 ca, int256 ea, int256 cb, int256 eb) external pure override returns (int256, int256) {
        (int256 c, int256 e) = LibDecimalFloatImplementation.add(ca, ea, -cb, eb);
        return (c + 1, e);
    }

    /// MINUS: the two outputs are byte-identical.
    function testMinusRejectsAChangedCoefficient() external {
        vm.expectRevert(stdError.assertionError);
        this.check_subIsAddNegated(1, 1, 0, 0, 0, 0);
    }
}
