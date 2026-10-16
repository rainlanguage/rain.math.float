// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {stdError} from "forge-std-1.17.0/src/StdError.sol";
import {Float} from "../../src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibHalmosExact} from "./LibHalmosExact.sol";
import {AgreeHalmosTest} from "./Agree.halmos.t.sol";
import {AgreeReturns} from "./AgreeReturns.sol";
import {AgreeLongRevert} from "./AgreeLongRevert.sol";
import {AgreeSwappedSelector} from "./AgreeSwappedSelector.sol";
import {AgreeWrongAbsolute} from "./AgreeWrongAbsolute.sol";
import {AgreeWrongProportional} from "./AgreeWrongProportional.sol";
import {AgreeSkewedExponent} from "./AgreeSkewedExponent.sol";
import {AgreeSkewedCoefficient} from "./AgreeSkewedCoefficient.sol";
import {AgreeSkewedShortfall} from "./AgreeSkewedShortfall.sol";
import {AgreeAddReverts} from "./AgreeAddReverts.sol";

/// Forge checks on the scaffolding of `Agree.halmos.t.sol`. A lemma that
/// returns early on every input, or a case split with a gap, passes halmos
/// with every job green, so these hold the filters and the splits to the
/// header's argument: the filters accept every maximized input, each NEG
/// slice and each SYMNEAR lemma proves exactly the cases its name says,
/// SYMFAR starts where SYMNEAR stops, and every lemma reaches the call it
/// checks at both ends of its domain and not past them (`vm.expectCall`
/// counts the nested call). A lemma that asserts less than the header says
/// passes too, the library being correct, so the sensitivity tests run each
/// lemma on the `Agree*` subjects beside this file, each of which breaks one
/// component of what a lemma asserts and keeps the rest as the library has
/// it, and expect the assertion panic: a lemma that drops a conjunct passes
/// its subject and fails here.
contract AgreeHalmosCoverTest is Test, AgreeHalmosTest {
    /// Tolerances for TOLERANCE's sensitivity: -1 and 5 as Floats at
    /// exponent 0, and the extremes 1 and 2 the lemma is given.
    bytes32 internal constant MINUS_ONE = bytes32(uint256(type(uint224).max));
    bytes32 internal constant FIVE = bytes32(uint256(5));
    bytes32 internal constant LOWEST = bytes32(uint256(1));
    bytes32 internal constant HIGHEST = bytes32(uint256(2));
    /// `maximize` of 1 at 0: 10^76, maximized by MAX.
    int256 internal constant A = 1e76;
    /// `symNear`'s yb for B = 10 yb = A.
    int256 internal constant YB = 1e75;
    /// The largest maximized magnitude, the last multiple of 10^8 at most
    /// 10 T10, and the smallest, the first above T10.
    // forge-lint: disable-next-line(unsafe-typecast, divide-before-multiply)
    int256 internal constant HIGH_IN = int256(10 * LibHalmosExact.T10 / 1e8 * 1e8);
    // forge-lint: disable-next-line(unsafe-typecast, divide-before-multiply)
    int256 internal constant LOW_IN = int256((LibHalmosExact.T10 / 1e8 + 1) * 1e8);

    /// Both maximized magnitudes in both signs: the operands at the edges of
    /// SYMNEAR's and SYMFAR's domain, closed under negation.
    function edges() internal pure returns (int256[4] memory) {
        return [HIGH_IN, -HIGH_IN, LOW_IN, -LOW_IN];
    }

    /// MAX's statement of maximized, in plain Solidity.
    function plainMaximized(int256 m) internal pure returns (bool) {
        uint256 x = LibHalmosExact.abs(m);
        return m != type(int256).min && x > LibHalmosExact.T10 && x <= 10 * LibHalmosExact.T10 && m % 1e8 == 0;
    }

    function testMaximizedEncodingsAgree(int256 m) external pure {
        assertEq(maximized(m), plainMaximized(m));
    }

    /// Both encodings at the bounds of MAX's statement: the multiples of 10^8
    /// either side of T10, the last one at most 10 T10 and 10 T10 itself (no
    /// multiple of 10^8 above it fits int256), both signs, and the extremes.
    function testMaximizedEncodingsAgreeAtBounds() external pure {
        int256 t10 = int256(LibHalmosExact.T10);
        int256[12] memory ms = [
            LOW_IN - 1e8,
            LOW_IN,
            HIGH_IN,
            10 * t10,
            -(LOW_IN - 1e8),
            -LOW_IN,
            -HIGH_IN,
            -10 * t10,
            int256(0),
            type(int256).min,
            type(int256).max,
            LOW_IN + 1
        ];
        bool[12] memory expected = [false, true, true, false, false, true, true, false, false, false, false, false];
        for (uint256 i = 0; i < ms.length; i++) {
            assertEq(plainMaximized(ms[i]), expected[i], vm.toString(ms[i]));
            assertEq(maximized(ms[i]), expected[i], vm.toString(ms[i]));
        }
    }

    /// Every output of `maximize` on a nonzero int224, and its negation, passes
    /// the filter SYMNEAR and SYMFAR return on.
    function testMaximizedOutputIsAdmissible(int224 c, int32 e) external pure {
        vm.assume(c != 0);
        (int256 m,,) = LibDecimalFloatImplementation.maximize(c, e);
        assertTrue(admissible(m));
        assertTrue(admissible(-m));
    }

    /// The same at both ends of every digit count class of [-2^223, 2^223],
    /// the coefficients MINUS hands `Impl.add`.
    function testMaximizedOutputIsAdmissibleAtDigitBounds() external pure {
        for (uint256 j = 0; j < NEG_DIGITS; j++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 low = int256(10 ** j);
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 high = j + 1 < NEG_DIGITS ? low * 10 - 1 : int256(2 ** 223);
            assertAdmissibleOutput(low, j);
            assertAdmissibleOutput(high, j);
            assertAdmissibleOutput(-low, j);
            assertAdmissibleOutput(-high, j);
        }
    }

    function assertAdmissibleOutput(int256 c, uint256 j) internal pure {
        assertTrue(LibHalmosExact.hasDigits(c, j), vm.toString(c));
        (int256 m,,) = LibDecimalFloatImplementation.maximize(c, 0);
        assertTrue(admissible(m), vm.toString(c));
        assertTrue(admissible(-m), vm.toString(c));
    }

    /// 10^(NEG_DIGITS - 1) <= 2^223 < 10^NEG_DIGITS.
    function testNegDigitsIsTheDigitCountOfTwo223() external pure {
        assertTrue(10 ** (NEG_DIGITS - 1) <= 2 ** 223);
        assertTrue(2 ** 223 < 10 ** NEG_DIGITS);
    }

    /// TOLERANCE reaches `agree` whenever a tolerance coefficient is
    /// negative or neither is positive: both zero, a zero at a nonzero
    /// exponent, -1 and int224.min in either place; a positive beside a zero
    /// or another positive returns before it.
    function testToleranceLemmaReachesEveryRevertClass() external {
        bytes32 zero = bytes32(0);
        bytes32 zeroAtFive = bytes32(uint256(5) << 224);
        bytes32 one = bytes32(uint256(1));
        bytes32 maxPositive = bytes32(uint256(type(uint224).max) >> 1);
        bytes32 minusOne = bytes32(uint256(type(uint224).max));
        bytes32 mostNegative = bytes32(uint256(1) << 223);
        expectToleranceReachesAgree(zero, zero, 1);
        expectToleranceReachesAgree(zeroAtFive, zero, 1);
        expectToleranceReachesAgree(zero, zeroAtFive, 1);
        expectToleranceReachesAgree(minusOne, zero, 1);
        expectToleranceReachesAgree(zero, minusOne, 1);
        expectToleranceReachesAgree(minusOne, one, 1);
        expectToleranceReachesAgree(one, minusOne, 1);
        expectToleranceReachesAgree(mostNegative, maxPositive, 1);
        expectToleranceReachesAgree(maxPositive, mostNegative, 1);
        expectToleranceReachesAgree(one, zero, 0);
        expectToleranceReachesAgree(zero, one, 0);
        expectToleranceReachesAgree(one, one, 0);
        expectToleranceReachesAgree(maxPositive, zeroAtFive, 0);
    }

    function expectToleranceReachesAgree(bytes32 a, bytes32 p, uint64 count) internal {
        bytes32 l = bytes32(uint256(1));
        bytes32 h = bytes32(uint256(2));
        vm.expectCall(
            address(this),
            abi.encodeCall(this.agree, (Float.wrap(a), Float.wrap(p), Float.wrap(l), Float.wrap(h))),
            count
        );
        this.check_agreeToleranceErrors(a, p, l, h);
    }

    /// ZERO reaches `Impl.sub` in both orders for zero, one of each sign and
    /// both int224 extremes.
    function testZeroLemmaReachesSubForEveryCoefficient() external {
        int224[5] memory cs = [int224(0), int224(1), int224(-1), type(int224).max, type(int224).min];
        for (uint256 i = 0; i < cs.length; i++) {
            int256 c = cs[i];
            vm.expectCall(address(this), abi.encodeCall(this.implSub, (c, int256(3), int256(0), int256(-7))), 1);
            vm.expectCall(address(this), abi.encodeCall(this.implSub, (int256(0), int256(-7), c, int256(3))), 1);
            this.check_spreadZeroEitherOrder(cs[i], 3, -7);
        }
    }

    /// The NEG slices from lo = 0 at every NEG_SLICE tile [0, NEG_DIGITS), and
    /// each digit count j, at both ends of its class, reaches `maximize` in
    /// exactly one lemma `check_maximizeNegates<lo>`.
    function testNegSlicesTileDigitCounts() external {
        uint256 next = 0;
        for (uint256 lo = 0; lo < NEG_DIGITS; lo += NEG_SLICE) {
            assertEq(lo, next);
            uint256 hi = negSliceHi(lo);
            assertTrue(hi >= lo && hi < NEG_DIGITS);
            next = hi + 1;
        }
        assertEq(next, NEG_DIGITS);
        for (uint256 j = 0; j < NEG_DIGITS; j++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 low = int256(10 ** j);
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 high = j + 1 < NEG_DIGITS ? low * 10 - 1 : int256(2 ** 223);
            expectMaximizedOnce(low, j);
            expectMaximizedOnce(high, j);
        }
    }

    /// Of the NEG lemmas, exactly one runs `maximize` on c and on -c.
    function expectMaximizedOnce(int256 c, uint256 j) internal {
        vm.expectCall(address(this), abi.encodeCall(this.maximize, (c, int256(0))), 1);
        vm.expectCall(address(this), abi.encodeCall(this.maximize, (-c, int256(0))), 1);
        for (uint256 lo = 0; lo < NEG_DIGITS; lo += NEG_SLICE) {
            string memory name = string.concat("check_maximizeNegates", vm.toString(lo), "(int256,int32,uint256)");
            (bool ok,) = address(this).call(abi.encodeWithSelector(selector(name), c, int32(0), j));
            assertTrue(ok, name);
        }
    }

    /// SYMFAR takes exactly the gaps from NEAR_GAPS to 2^40: `check_spreadSymFar`
    /// reaches `Impl.add` at those and returns before it either side.
    function testFarGapBounds() external {
        assertFalse(farGap(NEAR_GAPS - 1));
        assertTrue(farGap(NEAR_GAPS));
        assertTrue(farGap(2 ** 40));
        assertFalse(farGap(2 ** 40 + 1));
        expectFarAdds(A, A, 0, NEAR_GAPS - 1, 0);
        expectFarAdds(A, A, 0, NEAR_GAPS, 1);
        expectFarAdds(A, A, 0, 2 ** 40, 1);
        expectFarAdds(A, A, 0, 2 ** 40 + 1, 0);
    }

    /// SYMFAR at its first gap reaches both of `symAt`'s adds on every pair
    /// of edge operands at both ends of the exponent domain, and neither one
    /// exponent past either end.
    function testFarLemmaTakesTheWholeDomain() external {
        int256[4] memory xs = edges();
        int256[2] memory ebs = [FMIN - 76, FMAX - 8];
        for (uint256 k = 0; k < ebs.length; k++) {
            for (uint256 i = 0; i < xs.length; i++) {
                for (uint256 j = 0; j < xs.length; j++) {
                    expectFarAdds(xs[i], xs[j], ebs[k], NEAR_GAPS, 1);
                }
            }
        }
        expectFarAdds(HIGH_IN, HIGH_IN, FMIN - 77, NEAR_GAPS, 0);
        expectFarAdds(HIGH_IN, HIGH_IN, FMAX - 7, NEAR_GAPS, 0);
    }

    /// `check_spreadSymFar(a, b, eB, d)` makes `symAt`'s two adds `count`
    /// times each.
    function expectFarAdds(int256 a, int256 b, int256 eB, uint256 d, uint64 count) internal {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 eA = eB + int256(d);
        vm.expectCall(address(this), abi.encodeCall(this.implAdd, (a, eA, b, eB)), count);
        vm.expectCall(address(this), abi.encodeCall(this.implAdd, (-b, eB, -a, eA)), count);
        this.check_spreadSymFar(a, b, eB, d);
    }

    /// A lemma `check_spreadSymNear<d>` exists for every d in [0, NEAR_GAPS)
    /// and none at NEAR_GAPS, and each reaches `Impl.add` at the gap its name
    /// says.
    function testEveryNearGapHasALemmaAtItsGap() external {
        for (uint256 d = 0; d < NEAR_GAPS; d++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            vm.expectCall(address(this), abi.encodeCall(this.implAdd, (A, int256(d), A, int256(0))), 1);
            (bool ok,) = address(this).call(abi.encodeWithSelector(nearSelector(d), A, YB, int256(0)));
            assertTrue(ok, vm.toString(d));
        }
        (bool none,) = address(this).call(abi.encodeWithSelector(nearSelector(NEAR_GAPS), A, YB, int256(0)));
        assertFalse(none);
    }

    /// Every SYMNEAR lemma reaches both of `symAt`'s adds on every pair of
    /// edge operands at both ends of the exponent domain, and neither one
    /// exponent past either end.
    function testNearLemmasTakeTheWholeDomain() external {
        int256[4] memory xs = edges();
        int256[2] memory ebs = [FMIN - 76, FMAX - 8];
        for (uint256 d = 0; d < NEAR_GAPS; d++) {
            for (uint256 k = 0; k < ebs.length; k++) {
                for (uint256 i = 0; i < xs.length; i++) {
                    for (uint256 j = 0; j < xs.length; j++) {
                        expectNearAdds(d, xs[i], xs[j], ebs[k], 1);
                    }
                }
                for (uint256 i = 0; i < xs.length; i++) {
                    for (uint256 j = 0; j < xs.length; j++) {
                        callNear(d, xs[i], xs[j], ebs[k]);
                    }
                }
            }
            expectNearAdds(d, HIGH_IN, HIGH_IN, FMIN - 77, 0);
            callNear(d, HIGH_IN, HIGH_IN, FMIN - 77);
            expectNearAdds(d, HIGH_IN, HIGH_IN, FMAX - 7, 0);
            callNear(d, HIGH_IN, HIGH_IN, FMAX - 7);
        }
    }

    /// `symAt`'s two adds from `check_spreadSymNear<d>(a, b / 10, eB)`, each
    /// `count` times. At d = 0 the second add, of (-b, -a) at the one
    /// exponent, has the calldata of the first add of the pair (-b, -a), which
    /// `edges` also holds, so the one expectation stands for both: a call is
    /// counted only by the expectations before it, so a block's pairs are all
    /// expected before any is called.
    function expectNearAdds(uint256 d, int256 a, int256 b, int256 eB, uint64 count) internal {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 eA = eB + int256(d);
        if (d == 0) {
            vm.expectCall(address(this), abi.encodeCall(this.implAdd, (a, eA, b, eB)), 2 * count);
        } else {
            vm.expectCall(address(this), abi.encodeCall(this.implAdd, (a, eA, b, eB)), count);
            vm.expectCall(address(this), abi.encodeCall(this.implAdd, (-b, eB, -a, eA)), count);
        }
    }

    function callNear(uint256 d, int256 a, int256 b, int256 eB) internal {
        (bool ok,) = address(this).call(abi.encodeWithSelector(nearSelector(d), a, b / 10, eB));
        assertTrue(ok, vm.toString(d));
    }

    /// TOLERANCE fails on each of its five conjuncts alone: `agree`
    /// returning, a longer revert, the other class's selector in both
    /// classes, and each argument reported wrong.
    function testToleranceLemmaFailsOnEachBrokenConjunct() external {
        expectToleranceFails(new AgreeReturns(), MINUS_ONE, FIVE);
        expectToleranceFails(new AgreeLongRevert(), MINUS_ONE, FIVE);
        expectToleranceFails(new AgreeSwappedSelector(), MINUS_ONE, FIVE);
        expectToleranceFails(new AgreeSwappedSelector(), bytes32(0), bytes32(0));
        expectToleranceFails(new AgreeWrongAbsolute(), FIVE, MINUS_ONE);
        expectToleranceFails(new AgreeWrongProportional(), MINUS_ONE, FIVE);
    }

    function expectToleranceFails(AgreeHalmosTest subject, bytes32 a, bytes32 p) internal {
        vm.expectRevert(stdError.assertionError);
        subject.check_agreeToleranceErrors(a, p, LOWEST, HIGHEST);
    }

    /// ZERO fails on a coefficient off by one alone and on an exponent off by
    /// one alone, for a positive and a negative extreme.
    function testZeroLemmaFailsOnEachBrokenConjunct() external {
        expectZeroFails(new AgreeSkewedCoefficient());
        expectZeroFails(new AgreeSkewedExponent());
    }

    function expectZeroFails(AgreeHalmosTest subject) internal {
        vm.expectRevert(stdError.assertionError);
        subject.check_spreadZeroEitherOrder(1, 3, -7);
        vm.expectRevert(stdError.assertionError);
        subject.check_spreadZeroEitherOrder(type(int224).min, 3, -7);
    }

    /// NEG fails on the negation's coefficient, exponent or shortfall off by
    /// one alone, in the first slice at the first digit count and in the
    /// last slice at the last.
    function testNegLemmaFailsOnEachBrokenConjunct() external {
        expectNegFails(new AgreeSkewedCoefficient());
        expectNegFails(new AgreeSkewedExponent());
        expectNegFails(new AgreeSkewedShortfall());
    }

    function expectNegFails(AgreeHalmosTest subject) internal {
        vm.expectRevert(stdError.assertionError);
        subject.check_maximizeNegates0(1, 0, 0);
        vm.expectRevert(stdError.assertionError);
        subject.check_maximizeNegates51(2 ** 223, 0, NEG_DIGITS - 1);
    }

    /// SYMNEAR at its first and last gap and SYMFAR fail on the first add's
    /// coefficient off by one alone, on its exponent off by one alone, and on
    /// either add reverting: on positive operands the first add has the
    /// positive first operand, on negative ones the second does.
    function testSymLemmasFailOnEachBrokenConjunct() external {
        expectSymFails(new AgreeSkewedCoefficient(), HIGH_IN);
        expectSymFails(new AgreeSkewedExponent(), HIGH_IN);
        expectSymFails(new AgreeAddReverts(), HIGH_IN);
        expectSymFails(new AgreeAddReverts(), -HIGH_IN);
    }

    function expectSymFails(AgreeHalmosTest subject, int256 x) internal {
        vm.expectRevert(stdError.assertionError);
        subject.check_spreadSymNear00(x, x / 10, 0);
        vm.expectRevert(stdError.assertionError);
        subject.check_spreadSymNear76(x, x / 10, 0);
        vm.expectRevert(stdError.assertionError);
        subject.check_spreadSymFar(x, x, 0, NEAR_GAPS);
    }

    /// Every b `symNear` hands `sumHints`, at every gap, is in HINTS' domain
    /// for `negDivHint`, and the lemma runs at the domain's ends. int256.min
    /// alone is out: there the predicate fails from gap 1, so the lemma must
    /// return before it.
    function testNegDivHintDomainCoversSymNear() external view {
        int256[4] memory xs = edges();
        int256 t10 = int256(LibHalmosExact.T10);
        for (uint256 d = 0; d < NEAR_GAPS; d++) {
            for (uint256 i = 0; i < xs.length; i++) {
                assertTrue(negDivHintDomain(xs[i], d));
            }
            assertTrue(negDivHintDomain(10 * t10, d));
            assertTrue(negDivHintDomain(-10 * t10, d));
            assertTrue(negDivHintDomain(type(int256).min + 1, d));
            assertTrue(negDivHintDomain(0, d));
        }
        assertFalse(negDivHintDomain(1, NEAR_GAPS));
        assertFalse(negDivHintDomain(type(int256).min, 0));
        assertFalse(negDivHint(type(int256).min, 10));
        this.check_negDivHintHolds(HIGH_IN, 0);
        this.check_negDivHintHolds(-HIGH_IN, NEAR_GAPS - 1);
        this.check_negDivHintHolds(type(int256).min + 1, NEAR_GAPS - 1);
        this.check_negDivHintHolds(type(int256).min, 1);
        this.check_negDivHintHolds(type(int256).min, NEAR_GAPS - 1);
    }

    /// The two unfiltered HINTS lemmas run at the int256 extremes, zero and
    /// both units.
    function testUnfilteredHintLemmasRunAtTheExtremes() external view {
        int256[5] memory ms = [type(int256).min, int256(-1), int256(0), int256(1), type(int256).max];
        for (uint256 i = 0; i < ms.length; i++) {
            this.check_divHintsHold(ms[i]);
            this.check_overflowHintHolds(ms[i]);
        }
    }

    function nearSelector(uint256 d) internal pure returns (bytes4) {
        return
            selector(string.concat("check_spreadSymNear", d < 10 ? "0" : "", vm.toString(d), "(int256,int256,int256)"));
    }

    function selector(string memory signature) internal pure returns (bytes4) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return bytes4(keccak256(bytes(signature)));
    }
}
