// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {
    LibDecimalFloatImplementation,
    EXPONENT_MIN,
    EXPONENT_MAX,
    MAXIMIZED_ZERO_EXPONENT,
    MAXIMIZED_ZERO_SIGNED_COEFFICIENT
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {MaximizeOverflow} from "src/error/ErrDecimalFloat.sol";
import {LibDecimalFloatSlow} from "test/lib/LibDecimalFloatSlow.sol";

contract LibDecimalFloatImplementationMaximizeTest is Test {
    /// External wrapper so `vm.expectRevert` has a call boundary to catch the
    /// revert at. `LibDecimalFloatImplementation` is an internal library, so a
    /// direct call would be inlined into the test and revert at the same depth
    /// as the cheatcode.
    function maximizeFullExternal(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.maximizeFull(signedCoefficient, exponent);
    }

    function isMaximized(int256 signedCoefficient, int256 exponent) internal pure returns (bool) {
        if (signedCoefficient == 0) {
            return exponent == MAXIMIZED_ZERO_EXPONENT && signedCoefficient == MAXIMIZED_ZERO_SIGNED_COEFFICIENT;
        }

        if (signedCoefficient / 1e76 != 0) {
            return true;
        }

        if (signedCoefficient / 1e75 == 0) {
            return false;
        }

        return true;
    }

    /// Every normalized number is maximized.
    function testMaximizedEverything(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, EXPONENT_MIN, EXPONENT_MAX);
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.maximizeFull(signedCoefficient, exponent);
        assertTrue(isMaximized(actualSignedCoefficient, actualExponent));
    }

    function checkMaximized(
        int256 signedCoefficient,
        int256 exponent,
        int256 expectedCoefficient,
        int256 expectedExponent
    ) internal pure {
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.maximizeFull(signedCoefficient, exponent);
        assertEq(actualSignedCoefficient, expectedCoefficient);
        assertEq(actualExponent, expectedExponent);
    }

    function testMaximizedExamples() external pure {
        checkMaximized(0, 0, 0, 0);
        checkMaximized(0, 1, 0, 0);
        checkMaximized(1e37, 0, 1e76, -39);
        checkMaximized(1e76, 0, 1e76, 0);
        checkMaximized(type(int256).max, 0, type(int256).max, 0);
        checkMaximized(type(int256).min, 0, type(int256).min, 0);
        checkMaximized(42, 0, 4.2e76, -75);
        checkMaximized(42e74, -74, 4.2e76, -75);
        checkMaximized(4.2e76, -75, 4.2e76, -75);
        checkMaximized(88, 0, 8.8e75, -74);
        checkMaximized(88e74, -74, 8.8e75, -74);

        for (int256 i = 76; i >= 0; i--) {
            // i [0, 76]
            // forge-lint: disable-next-line(unsafe-typecast)
            checkMaximized(int256(10 ** uint256(i)), 0, 1e76, i - 76);
        }

        // Suspicious values flagged in fuzzing elsewhere.
        checkMaximized(54304950862250382, -16, 5.4304950862250382e76, -76);
    }

    /// Maximization should be idempotent.
    function testMaximizedIdempotent(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, EXPONENT_MIN, EXPONENT_MAX);
        (int256 maximizedSignedCoefficient, int256 maximizedExponent) =
            LibDecimalFloatImplementation.maximizeFull(signedCoefficient, exponent);
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.maximizeFull(maximizedSignedCoefficient, maximizedExponent);
        assertEq(actualSignedCoefficient, maximizedSignedCoefficient);
        assertEq(actualExponent, maximizedExponent);
    }

    /// Maximization against reference.
    function testMaximizedReference(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, EXPONENT_MIN, EXPONENT_MAX);
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.maximizeFull(signedCoefficient, exponent);
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibDecimalFloatSlow.maximizeSlow(signedCoefficient, exponent);
        assertEq(actualSignedCoefficient, expectedSignedCoefficient);
        assertEq(actualExponent, expectedExponent);
    }

    /// Partial maximization happens when the exponent is so close to
    /// `type(int256).min` that the coefficient cannot be pushed up to a full
    /// magnitude (`>= 1e75`) without underflowing the exponent. In that case
    /// `maximize` returns `full == false` and leaves the result as maximized as
    /// it can be. The bounded fuzz tests above can never reach this because they
    /// bound the exponent to `[EXPONENT_MIN, EXPONENT_MAX]` and call
    /// `maximizeFull`, which reverts on a partial result.
    function checkPartial(
        int256 signedCoefficient,
        int256 exponent,
        int256 expectedCoefficient,
        int256 expectedExponent
    ) internal {
        (int256 actualSignedCoefficient, int256 actualExponent, bool full) =
            LibDecimalFloatImplementation.maximize(signedCoefficient, exponent);
        assertFalse(full, "expected partial maximization");
        assertEq(actualSignedCoefficient, expectedCoefficient, "partial coefficient");
        assertEq(actualExponent, expectedExponent, "partial exponent");
        assertFalse(isMaximized(actualSignedCoefficient, actualExponent), "partial result is not fully maximized");

        // `maximizeFull` must revert on exactly the inputs that maximize only
        // partially.
        vm.expectRevert(abi.encodeWithSelector(MaximizeOverflow.selector, signedCoefficient, exponent));
        this.maximizeFullExternal(signedCoefficient, exponent);
    }

    function testMaximizePartialExamples() external {
        int256 min = type(int256).min;

        // No room at all to grow: exponent is already at the floor.
        checkPartial(1, min, 1, min);
        checkPartial(-1, min, -1, min);

        // A single order of magnitude fits but no more.
        checkPartial(1, min + 1, 10, min);
        checkPartial(-1, min + 1, -10, min);

        // Several orders of magnitude fit, but still short of 1e75.
        checkPartial(1, min + 38, 1e38, min);
        checkPartial(1, min + 74, 1e74, min);

        // Already-large-ish coefficients that still can't reach 1e75.
        checkPartial(1e74, min, 1e74, min);
        checkPartial(99e72, min, 99e72, min);
    }

    /// The very first exponent at which `1` becomes fully maximizable is
    /// `type(int256).min + 75`, landing on `1e75` with the exponent saturated at
    /// the floor. One below that is partial.
    function testMaximizePartialBoundary() external {
        int256 min = type(int256).min;

        // Partial: 1e74 is below the 1e75 "full" threshold.
        checkPartial(1, min + 74, 1e74, min);

        // Full: exactly 1e75, exponent saturates at the floor.
        (int256 c, int256 e, bool full) = LibDecimalFloatImplementation.maximize(1, min + 75);
        assertTrue(full);
        assertEq(c, 1e75);
        assertEq(e, min);
        assertTrue(isMaximized(c, e));
        // `maximizeFull` agrees with `maximize` once it is full.
        (int256 cFull, int256 eFull) = LibDecimalFloatImplementation.maximizeFull(1, min + 75);
        assertEq(cFull, c);
        assertEq(eFull, e);
    }

    /// Fuzz the partial region: pick a tiny exponent near the floor so that small
    /// coefficients cannot be fully maximized, and assert the invariants that
    /// must hold whenever `maximize` returns `full == false`.
    function testMaximizePartialFuzz(int256 signedCoefficient, uint256 headroom) external pure {
        // Keep the coefficient small enough that it can never reach 1e75 within
        // the tiny exponent headroom we allow below.
        signedCoefficient = bound(signedCoefficient, -1e10, 1e10);
        // Zero always maximizes fully (to maximized zero), so it is never
        // partial. Exclude it from this partial-region fuzz.
        vm.assume(signedCoefficient != 0);

        // Exponent sits within 64 of the floor: not enough room to add the ~65+
        // orders of magnitude a <=1e10 coefficient would need to reach 1e75.
        headroom = bound(headroom, 0, 64);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exponent = type(int256).min + int256(headroom);

        (int256 actualCoefficient, int256 actualExponent, bool full) =
            LibDecimalFloatImplementation.maximize(signedCoefficient, exponent);

        // These inputs are always partial.
        assertFalse(full, "must be partial");
        assertFalse(isMaximized(actualCoefficient, actualExponent), "not fully maximized");

        // Partial results never reach the full-magnitude threshold.
        assertTrue(actualCoefficient / 1e75 == 0, "below full threshold");
        // A non-zero input stays non-zero.
        assertTrue(actualCoefficient != 0, "stays non-zero");

        // The exponent only ever decreases (magnitude pushed up), and a partial
        // result is pinned at the floor: there is no room left for even one more
        // order of magnitude without underflowing the exponent.
        assertTrue(actualExponent <= exponent, "exponent did not increase");
        assertEq(actualExponent, type(int256).min, "partial result pinned to exponent floor");

        // Value preservation: maximization only multiplies the coefficient by a
        // power of ten while subtracting the same power from the exponent, so the
        // represented value is unchanged. The shift is exactly the exponent
        // delta.
        int256 shift = exponent - actualExponent;
        assertTrue(shift >= 0, "non-negative shift");
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(actualCoefficient, signedCoefficient * int256(10 ** uint256(shift)), "value preserved");
    }

    /// Re-maximizing a partial result is a no-op and stays partial: there is no
    /// hidden extra normalization available once the exponent floor is hit.
    function testMaximizePartialIdempotent(int256 signedCoefficient, uint256 headroom) external pure {
        signedCoefficient = bound(signedCoefficient, -1e10, 1e10);
        vm.assume(signedCoefficient != 0);
        headroom = bound(headroom, 0, 64);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exponent = type(int256).min + int256(headroom);

        (int256 firstCoefficient, int256 firstExponent, bool firstFull) =
            LibDecimalFloatImplementation.maximize(signedCoefficient, exponent);
        assertFalse(firstFull, "first pass partial");

        (int256 secondCoefficient, int256 secondExponent, bool secondFull) =
            LibDecimalFloatImplementation.maximize(firstCoefficient, firstExponent);
        assertEq(secondCoefficient, firstCoefficient, "idempotent coefficient");
        assertEq(secondExponent, firstExponent, "idempotent exponent");
        assertFalse(secondFull, "stays partial");
    }

    /// Fully independent oracle for `maximize`, deliberately *not* sharing any
    /// structure with the production binary staircase. It greedily multiplies the
    /// coefficient by ten one order of magnitude at a time, overflow-safely, and
    /// stops as soon as either the next multiply would overflow `int256` or the
    /// exponent would underflow `type(int256).min`. This is the definition of
    /// "as maximized as possible while preserving the value and not underflowing
    /// the exponent", so it pins down the exact (coefficient, exponent, full)
    /// triple production must return. Unlike `maximizeSlow` (which decrements the
    /// exponent in unchecked arithmetic and so wraps past the floor) this oracle
    /// is correct right at `type(int256).min`.
    function maximizeOracle(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256, bool) {
        unchecked {
            if (signedCoefficient == 0) {
                return (MAXIMIZED_ZERO_SIGNED_COEFFICIENT, MAXIMIZED_ZERO_EXPONENT, true);
            }
            // Greedy single-OOM steps. Bounded by 76 iterations because anything
            // representable in int256 is < 1e77 in magnitude.
            while (exponent > type(int256).min) {
                int256 next = signedCoefficient * 10;
                // Overflow-safe check on the multiply: if it round-trips, it did
                // not overflow.
                if (next / 10 != signedCoefficient) {
                    break;
                }
                signedCoefficient = next;
                exponent -= 1;
            }
            // Full iff the magnitude reached the 1e75 threshold.
            return (signedCoefficient, exponent, signedCoefficient / 1e75 != 0);
        }
    }

    /// `maximize` must agree with the independent oracle across the *entire*
    /// `int256` coefficient and exponent domains, including the
    /// `type(int256).min` / `type(int256).max` corners and exponents far below
    /// `EXPONENT_MIN` that the existing bounded tests never reach. This is the
    /// strongest discriminator: it catches any wrong coefficient, wrong exponent
    /// (overshoot or undershoot at the floor) or wrong `full` flag.
    function testMaximizeOracleFullDomain(int256 signedCoefficient, int256 exponent) external pure {
        (int256 actualCoefficient, int256 actualExponent, bool actualFull) =
            LibDecimalFloatImplementation.maximize(signedCoefficient, exponent);
        (int256 expectedCoefficient, int256 expectedExponent, bool expectedFull) =
            maximizeOracle(signedCoefficient, exponent);
        assertEq(actualCoefficient, expectedCoefficient, "oracle coefficient");
        assertEq(actualExponent, expectedExponent, "oracle exponent");
        assertEq(actualFull, expectedFull, "oracle full flag");
    }

    /// Same oracle agreement but with the coefficient hammered onto `int224`
    /// boundaries (the packed coefficient width) and the exponent hammered onto
    /// `int32`/`int256` boundaries, instead of staying in the easy middle of the
    /// range. These are exactly the corners the existing suite avoids.
    function testMaximizeOracleBoundaryCorners(uint8 cSel, uint8 eSel) external pure {
        int256[8] memory cs = [
            int256(type(int224).max),
            type(int224).min,
            int256(type(int224).max) - 1,
            type(int224).min + 1,
            type(int256).max,
            type(int256).min,
            type(int256).min + 1,
            int256(1)
        ];
        int256[8] memory es = [
            int256(type(int32).max),
            type(int32).min,
            type(int256).max,
            type(int256).min,
            type(int256).min + 1,
            type(int256).min + 38,
            type(int256).min + 75,
            int256(0)
        ];
        int256 c = cs[cSel % 8];
        int256 e = es[eSel % 8];

        (int256 actualCoefficient, int256 actualExponent, bool actualFull) =
            LibDecimalFloatImplementation.maximize(c, e);
        (int256 expectedCoefficient, int256 expectedExponent, bool expectedFull) = maximizeOracle(c, e);
        assertEq(actualCoefficient, expectedCoefficient, "corner coefficient");
        assertEq(actualExponent, expectedExponent, "corner exponent");
        assertEq(actualFull, expectedFull, "corner full flag");
    }

    /// Deterministically walk *every* exponent headroom from 0 to 80 above the
    /// floor for several small coefficients, comparing against the independent
    /// oracle exactly. Each staircase guard in production carries an exponent
    /// bound of the form `exponent >= type(int256).min + N` (N in
    /// {1, 2, 10, 19, 38}). An off-by-one in any of those bounds, in either
    /// direction, changes the maximized result for exactly one headroom value, so
    /// covering the whole headroom range with a dense, deterministic sweep kills
    /// every such per-step mutant without relying on fuzz luck to land on the one
    /// breaking exponent.
    function testMaximizeStaircaseBoundarySweep() external pure {
        int256[5] memory cs = [int256(1), int256(-1), int256(7), int256(-7), int256(123456)];
        for (uint256 i = 0; i < cs.length; i++) {
            int256 c = cs[i];
            for (uint256 headroom = 0; headroom <= 80; headroom++) {
                // forge-lint: disable-next-line(unsafe-typecast)
                int256 e = type(int256).min + int256(headroom);
                (int256 actualCoefficient, int256 actualExponent, bool actualFull) =
                    LibDecimalFloatImplementation.maximize(c, e);
                (int256 expectedCoefficient, int256 expectedExponent, bool expectedFull) = maximizeOracle(c, e);
                assertEq(actualCoefficient, expectedCoefficient, "sweep coefficient");
                assertEq(actualExponent, expectedExponent, "sweep exponent");
                assertEq(actualFull, expectedFull, "sweep full flag");
            }
        }
    }

    /// Value preservation in the *full* case across the whole exponent domain,
    /// not just the partial region the existing value-preservation fuzz covers.
    /// Maximization may only multiply the coefficient by a non-negative power of
    /// ten while subtracting the same power from the exponent, so the represented
    /// value is unchanged: the coefficient out must be exactly the coefficient in
    /// scaled by 10^(exponent_in - exponent_out), and that shift must be in
    /// [0, 76] with no overflow.
    function testMaximizeValuePreservedFullDomain(int256 signedCoefficient, int256 exponent) external pure {
        // Zero is canonicalized to maximized zero (0, 0) regardless of the input
        // exponent, which is value-preserving (0 == 0) but resets rather than
        // only-decreases the exponent. It is handled by the dedicated zero
        // examples below, so exclude it from the non-zero monotonicity checks.
        vm.assume(signedCoefficient != 0);

        (int256 actualCoefficient, int256 actualExponent, bool full) =
            LibDecimalFloatImplementation.maximize(signedCoefficient, exponent);

        // The exponent never increases.
        assertTrue(actualExponent <= exponent, "exponent did not increase");
        int256 shift = exponent - actualExponent;
        assertTrue(shift >= 0 && shift <= 76, "shift in [0, 76]");

        // Value preserved: coefficient_out == coefficient_in * 10^shift, checked
        // overflow-safely so a wrong (too large) shift cannot sneak past.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 scale = int256(10 ** uint256(shift));
        int256 rescaled = signedCoefficient * scale;
        assertEq(rescaled / scale, signedCoefficient, "no overflow in value-preservation scale");
        assertEq(actualCoefficient, rescaled, "value preserved");

        // The full flag is exactly the magnitude predicate.
        assertEq(full, actualCoefficient / 1e75 != 0, "full flag matches magnitude");
    }

    /// Zero canonicalizes to maximized zero `(0, 0, true)` for any input
    /// exponent, including the exponent extremes. This is the value-preserving
    /// (0 == 0) special case excluded from the non-zero fuzz above.
    function testMaximizeZeroCanonicalizes(int256 exponent) external pure {
        (int256 c, int256 e, bool full) = LibDecimalFloatImplementation.maximize(0, exponent);
        assertEq(c, MAXIMIZED_ZERO_SIGNED_COEFFICIENT, "zero coefficient canonical");
        assertEq(e, MAXIMIZED_ZERO_EXPONENT, "zero exponent canonical");
        assertTrue(full, "zero is full");
    }

    /// `maximizeFull` reverts with `MaximizeOverflow(originalInputs)` for *every*
    /// input whose maximization is partial, and returns the maximized pair for
    /// every input that is full. Driven across the boundary corners, including
    /// exponents below `EXPONENT_MIN` where partial results actually occur (the
    /// existing `maximizeFull` tests only ever hit the full case).
    function testMaximizeFullRevertsIffPartial(uint8 cSel, uint8 eSel) external {
        int256[6] memory cs =
            [int256(type(int224).max), type(int224).min, type(int256).max, type(int256).min, int256(1), int256(-1)];
        int256[6] memory es = [
            type(int256).min,
            type(int256).min + 1,
            type(int256).min + 74,
            type(int256).min + 75,
            type(int256).min + 76,
            int256(0)
        ];
        int256 c = cs[cSel % 6];
        int256 e = es[eSel % 6];

        (int256 expectedCoefficient, int256 expectedExponent, bool expectedFull) = maximizeOracle(c, e);

        if (expectedFull) {
            (int256 actualCoefficient, int256 actualExponent) = this.maximizeFullExternal(c, e);
            assertEq(actualCoefficient, expectedCoefficient, "full coefficient");
            assertEq(actualExponent, expectedExponent, "full exponent");
        } else {
            vm.expectRevert(abi.encodeWithSelector(MaximizeOverflow.selector, c, e));
            this.maximizeFullExternal(c, e);
        }
    }

    /// The "one more order of magnitude" tail step has an inherent sign
    /// asymmetry: `type(int256).min` has magnitude one larger than
    /// `type(int256).max`, so a negative coefficient can sometimes take one extra
    /// OOM that its positive mirror cannot. Pin both sides down concretely so a
    /// mutant that drops or mis-guards the tail step is caught. `5e75` already
    /// has magnitude >= 1e75 so the staircase is skipped and only the tail step
    /// runs.
    function testMaximizeOneMoreOomSignAsymmetry() external pure {
        // Positive: 5e75 * 10 = 5e76 < type(int256).max, fits, one OOM taken.
        (int256 cp, int256 ep, bool fp) = LibDecimalFloatImplementation.maximize(5e75, 0);
        assertEq(cp, 5e76, "positive tail coefficient");
        assertEq(ep, -1, "positive tail exponent");
        assertTrue(fp, "positive tail full");

        // 6e75 * 10 = 6e76 > type(int256).max, overflows, tail step is rejected.
        (int256 co, int256 eo, bool fo) = LibDecimalFloatImplementation.maximize(6e75, 0);
        assertEq(co, 6e75, "positive no-tail coefficient");
        assertEq(eo, 0, "positive no-tail exponent");
        assertTrue(fo, "positive no-tail full");

        // Negative mirror of 6e75: -6e75 * 10 = -6e76 > type(int256).min in
        // magnitude? type(int256).min ~= -5.79e76, so -6e76 < min: overflows,
        // tail rejected, mirroring the positive case.
        (int256 cn, int256 en, bool fn) = LibDecimalFloatImplementation.maximize(-6e75, 0);
        assertEq(cn, -6e75, "negative no-tail coefficient");
        assertEq(en, 0, "negative no-tail exponent");
        assertTrue(fn, "negative no-tail full");

        // No exponent headroom: tail step must be blocked even though the
        // multiply would not overflow. 5e75 * 10 fits but exponent is already at
        // the floor, so the value must be left untouched.
        (int256 cf, int256 ef, bool ff) = LibDecimalFloatImplementation.maximize(5e75, type(int256).min);
        assertEq(cf, 5e75, "floor-pinned coefficient (no tail)");
        assertEq(ef, type(int256).min, "floor-pinned exponent (no tail)");
        assertTrue(ff, "floor-pinned full");
    }

    /// Partial-region fuzz reaching up to the `int224` coefficient boundary
    /// rather than capping at 1e10. Asserts the `full` flag is the exact
    /// magnitude predicate (not always-false), that the result is value
    /// preserving, and that the result is pinned to the floor exactly when it is
    /// partial. This exercises larger coefficients that *do* cross into the full
    /// region for larger headroom, so the test discriminates the full-vs-partial
    /// decision near the floor.
    function testMaximizePartialBoundaryCoefficients(int256 signedCoefficient, uint256 headroom) external pure {
        signedCoefficient = bound(signedCoefficient, type(int224).min, type(int224).max);
        vm.assume(signedCoefficient != 0);
        headroom = bound(headroom, 0, 80);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exponent = type(int256).min + int256(headroom);

        (int256 actualCoefficient, int256 actualExponent, bool full) =
            LibDecimalFloatImplementation.maximize(signedCoefficient, exponent);

        // Value preserved.
        int256 shift = exponent - actualExponent;
        assertTrue(shift >= 0 && shift <= 76, "shift in [0, 76]");
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 scale = int256(10 ** uint256(shift));
        assertEq(actualCoefficient, signedCoefficient * scale, "value preserved");

        // Full flag is exactly the magnitude predicate.
        assertEq(full, actualCoefficient / 1e75 != 0, "full flag matches magnitude");

        // A partial result is always pinned to the floor: there is no headroom
        // left to grow even one more order of magnitude.
        if (!full) {
            assertEq(actualExponent, type(int256).min, "partial pinned to floor");
            // And there genuinely was not enough headroom: growing one more OOM
            // either overflows the coefficient or underflows the exponent.
            assertTrue(actualExponent == type(int256).min, "partial at floor");
        }
    }
}
