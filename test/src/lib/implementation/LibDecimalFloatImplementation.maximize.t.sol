// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {
    LibDecimalFloatImplementation,
    EXPONENT_MIN,
    EXPONENT_MAX,
    MAXIMIZED_ZERO_EXPONENT,
    MAXIMIZED_ZERO_SIGNED_COEFFICIENT
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {MaximizeOverflow} from "src/error/ErrDecimalFloat.sol";
import {LibDecimalFloatSlow} from "test/lib/LibDecimalFloatSlow.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";

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

    /// Near the floor the coefficient is still fully maximized, and the shift
    /// the exponent cannot take is returned as the shortfall.
    function checkShortfall(
        int256 signedCoefficient,
        int256 exponent,
        int256 expectedCoefficient,
        int256 expectedShortfall
    ) internal {
        (int256 actualSignedCoefficient, int256 actualExponent, int256 shortfall) =
            LibDecimalFloatImplementation.maximize(signedCoefficient, exponent);
        assertEq(actualSignedCoefficient, expectedCoefficient, "coefficient");
        assertEq(actualExponent, type(int256).min, "exponent");
        assertEq(shortfall, expectedShortfall, "shortfall");

        vm.expectRevert(abi.encodeWithSelector(MaximizeOverflow.selector, signedCoefficient, exponent));
        this.maximizeFullExternal(signedCoefficient, exponent);
    }

    function testMaximizeShortfallExamples() external {
        int256 min = type(int256).min;

        checkShortfall(1, min, 1e76, 76);
        checkShortfall(-1, min, -1e76, 76);
        checkShortfall(1, min + 1, 1e76, 75);
        checkShortfall(-1, min + 1, -1e76, 75);
        checkShortfall(1, min + 38, 1e76, 38);
        checkShortfall(1, min + 75, 1e76, 1);
        checkShortfall(1e74, min, 1e76, 2);
        checkShortfall(99e72, min, 99e74, 2);
        // A 76 digit coefficient at the floor still takes its 77th digit.
        checkShortfall(5e75, min, 5e76, 1);
    }

    /// The first exponent at which `1` has no shortfall is
    /// `type(int256).min + 76`.
    function testMaximizeShortfallBoundary() external {
        int256 min = type(int256).min;
        checkShortfall(1, min + 75, 1e76, 1);

        (int256 c, int256 e, int256 shortfall) = LibDecimalFloatImplementation.maximize(1, min + 76);
        assertEq(c, 1e76);
        assertEq(e, min);
        assertEq(shortfall, 0);
        (int256 cFull, int256 eFull) = LibDecimalFloatImplementation.maximizeFull(1, min + 76);
        assertEq(cFull, c);
        assertEq(eFull, e);
    }

    /// Re-maximizing a result is a no-op with no shortfall, because the
    /// coefficient is already fully maximized.
    function testMaximizeShortfallIdempotent(int256 signedCoefficient, uint256 headroom) external pure {
        headroom = bound(headroom, 0, 80);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exponent = type(int256).min + int256(headroom);

        (int256 firstCoefficient, int256 firstExponent,) =
            LibDecimalFloatImplementation.maximize(signedCoefficient, exponent);
        (int256 secondCoefficient, int256 secondExponent, int256 secondShortfall) =
            LibDecimalFloatImplementation.maximize(firstCoefficient, firstExponent);
        assertEq(secondCoefficient, firstCoefficient, "idempotent coefficient");
        assertEq(secondExponent, firstExponent, "idempotent exponent");
        assertEq(secondShortfall, 0, "no second shortfall");
    }

    function checkOracle(int256 signedCoefficient, int256 exponent) internal pure {
        (int256 actualCoefficient, int256 actualExponent, int256 actualShortfall) =
            LibDecimalFloatImplementation.maximize(signedCoefficient, exponent);
        (int256 expectedCoefficient, int256 expectedExponent, int256 expectedShortfall) =
            LibTestExactDecimal.maximize(signedCoefficient, exponent);
        assertEq(actualCoefficient, expectedCoefficient, "oracle coefficient");
        assertEq(actualExponent, expectedExponent, "oracle exponent");
        assertEq(actualShortfall, expectedShortfall, "oracle shortfall");
    }

    /// `maximize` agrees with the oracle across the entire `int256`
    /// coefficient and exponent domains.
    function testMaximizeOracleFullDomain(int256 signedCoefficient, int256 exponent) external pure {
        checkOracle(signedCoefficient, exponent);
    }

    /// Oracle agreement near the floor, where the shortfall happens.
    function testMaximizeOracleNearFloor(int256 signedCoefficient, uint256 headroom) external pure {
        headroom = bound(headroom, 0, 80);
        // forge-lint: disable-next-line(unsafe-typecast)
        checkOracle(signedCoefficient, type(int256).min + int256(headroom));
    }

    /// Oracle agreement with the coefficient on `int224`/`int256` boundaries
    /// and the exponent on `int32`/`int256` boundaries.
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
        checkOracle(cs[cSel % 8], es[eSel % 8]);
    }

    /// Every exponent headroom from 0 to 80 above the floor for several
    /// coefficients, against the oracle.
    function testMaximizeStaircaseBoundarySweep() external pure {
        int256[7] memory cs =
            [int256(1), int256(-1), int256(7), int256(-7), int256(123456), int256(5e75), int256(-6e75)];
        for (uint256 i = 0; i < cs.length; i++) {
            for (uint256 headroom = 0; headroom <= 80; headroom++) {
                // forge-lint: disable-next-line(unsafe-typecast)
                checkOracle(cs[i], type(int256).min + int256(headroom));
            }
        }
    }

    /// Value preservation across the whole domain: the coefficient out is the
    /// coefficient in scaled by 10^(exponent_in - exponent_out + shortfall),
    /// a shift in [0, 76]. The coefficient out is always at least 1e75 in
    /// magnitude, and a shortfall only happens at the floor.
    function testMaximizeValuePreservedFullDomain(int256 signedCoefficient, int256 exponent) external pure {
        vm.assume(signedCoefficient != 0);

        (int256 actualCoefficient, int256 actualExponent, int256 shortfall) =
            LibDecimalFloatImplementation.maximize(signedCoefficient, exponent);

        assertTrue(actualExponent <= exponent, "exponent did not increase");
        assertTrue(shortfall >= 0 && shortfall <= 76, "shortfall in [0, 76]");
        if (shortfall != 0) {
            assertEq(actualExponent, type(int256).min, "shortfall only at the floor");
        }
        int256 shift = exponent - actualExponent + shortfall;
        assertTrue(shift >= 0 && shift <= 76, "shift in [0, 76]");

        // forge-lint: disable-next-line(unsafe-typecast)
        int256 scale = int256(10 ** uint256(shift));
        int256 rescaled = signedCoefficient * scale;
        assertEq(rescaled / scale, signedCoefficient, "no overflow in value-preservation scale");
        assertEq(actualCoefficient, rescaled, "value preserved");
        assertTrue(actualCoefficient / 1e75 != 0, "full magnitude");
    }

    /// Zero canonicalizes to maximized zero `(0, 0, 0)` for any input
    /// exponent.
    function testMaximizeZeroCanonicalizes(int256 exponent) external pure {
        (int256 c, int256 e, int256 shortfall) = LibDecimalFloatImplementation.maximize(0, exponent);
        assertEq(c, MAXIMIZED_ZERO_SIGNED_COEFFICIENT, "zero coefficient canonical");
        assertEq(e, MAXIMIZED_ZERO_EXPONENT, "zero exponent canonical");
        assertEq(shortfall, 0, "zero has no shortfall");
    }

    /// `maximizeFull` reverts with `MaximizeOverflow(originalInputs)` for
    /// every input with a shortfall, and returns the maximized pair otherwise.
    function testMaximizeFullRevertsIffShortfall(uint8 cSel, uint8 eSel) external {
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

        (int256 expectedCoefficient, int256 expectedExponent, int256 expectedShortfall) =
            LibTestExactDecimal.maximize(c, e);

        if (expectedShortfall == 0) {
            (int256 actualCoefficient, int256 actualExponent) = this.maximizeFullExternal(c, e);
            assertEq(actualCoefficient, expectedCoefficient, "full coefficient");
            assertEq(actualExponent, expectedExponent, "full exponent");
        } else {
            vm.expectRevert(abi.encodeWithSelector(MaximizeOverflow.selector, c, e));
            this.maximizeFullExternal(c, e);
        }
    }

    /// The "one more order of magnitude" tail step has a sign asymmetry:
    /// `type(int256).min` has magnitude one larger than `type(int256).max`.
    /// `5e75` already has magnitude >= 1e75 so only the tail step runs.
    function testMaximizeOneMoreOomSignAsymmetry() external pure {
        (int256 cp, int256 ep, int256 sp) = LibDecimalFloatImplementation.maximize(5e75, 0);
        assertEq(cp, 5e76, "positive tail coefficient");
        assertEq(ep, -1, "positive tail exponent");
        assertEq(sp, 0, "positive tail shortfall");

        (int256 co, int256 eo, int256 so) = LibDecimalFloatImplementation.maximize(6e75, 0);
        assertEq(co, 6e75, "positive no-tail coefficient");
        assertEq(eo, 0, "positive no-tail exponent");
        assertEq(so, 0, "positive no-tail shortfall");

        (int256 cn, int256 en, int256 sn) = LibDecimalFloatImplementation.maximize(-6e75, 0);
        assertEq(cn, -6e75, "negative no-tail coefficient");
        assertEq(en, 0, "negative no-tail exponent");
        assertEq(sn, 0, "negative no-tail shortfall");

        // At the floor the tail step is a one digit shortfall.
        (int256 cf, int256 ef, int256 sf) = LibDecimalFloatImplementation.maximize(5e75, type(int256).min);
        assertEq(cf, 5e76, "floor tail coefficient");
        assertEq(ef, type(int256).min, "floor tail exponent");
        assertEq(sf, 1, "floor tail shortfall");
    }

    /// The tail step takes exactly the coefficients whose tenfold fits in
    /// int256: `type(int256).max / 10` and `type(int256).min / 10` do, one
    /// further out on either side does not.
    function testMaximizeOneMoreOomExactBounds() external pure {
        int256 hi = type(int256).max / 10;
        int256 lo = type(int256).min / 10;

        (int256 c, int256 e, int256 s) = LibDecimalFloatImplementation.maximize(hi, 0);
        assertEq(c, hi * 10, "hi coefficient");
        assertEq(e, -1, "hi exponent");
        assertEq(s, 0, "hi shortfall");

        (c, e, s) = LibDecimalFloatImplementation.maximize(hi + 1, 0);
        assertEq(c, hi + 1, "past hi coefficient");
        assertEq(e, 0, "past hi exponent");
        assertEq(s, 0, "past hi shortfall");

        (c, e, s) = LibDecimalFloatImplementation.maximize(lo, 0);
        assertEq(c, lo * 10, "lo coefficient");
        assertEq(e, -1, "lo exponent");
        assertEq(s, 0, "lo shortfall");

        (c, e, s) = LibDecimalFloatImplementation.maximize(lo - 1, 0);
        assertEq(c, lo - 1, "past lo coefficient");
        assertEq(e, 0, "past lo exponent");
        assertEq(s, 0, "past lo shortfall");
    }
}
