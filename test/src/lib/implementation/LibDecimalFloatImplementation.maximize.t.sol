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
}
