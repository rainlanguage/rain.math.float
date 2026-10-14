// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    LibDecimalFloatImplementation,
    LOG10_RATIO_Z_MAX,
    LOG10_SKIP_BELOW
} from "../../../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Exp10FixedOutOfRange, Log10RatioOutOfRange} from "../../../../src/error/ErrDecimalFloat.sol";
import {LibDecimalFloatImplementationSeriesLoop} from "../../../lib/LibDecimalFloatImplementationSeriesLoop.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";

/// `log10Ratio` and `exp10Fixed` return exactly what the baseline's copies
/// return, from before their multiplies were written out in place, over the
/// domain each guards. Outside it both revert the named range error with the
/// input.
contract LibDecimalFloatImplementationSeriesLoopEquivalenceTest is Test {
    function liveRatio(uint256 a, uint256 b, bool relative) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.log10Ratio(a, b, relative);
    }

    function loopRatio(uint256 a, uint256 b, bool relative) external pure returns (int256, int256) {
        return LibDecimalFloatImplementationSeriesLoop.log10Ratio(a, b, relative);
    }

    function liveExp10(uint256 x) external pure returns (uint256) {
        return LibDecimalFloatImplementation.exp10Fixed(x);
    }

    function loopExp10(uint256 x) external pure returns (uint256) {
        return LibDecimalFloatImplementationSeriesLoop.exp10Fixed(x);
    }

    /// z = |a - b| / (a + b) floored at 1e-50 past `LOG10_RATIO_Z_MAX`, for
    /// a + b at least 1e50 and below 2^256.
    function outOfRange(uint256 a, uint256 b) internal pure returns (bool) {
        uint256 difference = a < b ? b - a : a - b;
        return LibDecimalFloatImplementation.mulDiv(difference, 1e50, a + b) > LOG10_RATIO_Z_MAX;
    }

    function checkRatio(uint256 a, uint256 b) internal view {
        bool expectRevert = outOfRange(a, b);
        for (uint256 i = 0; i < 2; i++) {
            (bool okLive, bytes memory live) = address(this).staticcall(abi.encodeCall(this.liveRatio, (a, b, i == 0)));
            (bool okLoop, bytes memory loop) = address(this).staticcall(abi.encodeCall(this.loopRatio, (a, b, i == 0)));
            if (expectRevert) {
                assertFalse(okLive, "live out of range");
                assertEq(live, abi.encodeWithSelector(Log10RatioOutOfRange.selector, a, b), "live out of range bytes");
                assertFalse(okLoop, "loop out of range");
            } else {
                assertTrue(okLive, "live in range");
            }
            assertEq(okLive, okLoop, "success");
            assertEq(live, loop, "bytes");
        }
    }

    function checkExp10(uint256 x) internal view {
        (bool okLive, bytes memory live) = address(this).staticcall(abi.encodeCall(this.liveExp10, (x)));
        (bool okLoop, bytes memory loop) = address(this).staticcall(abi.encodeCall(this.loopExp10, (x)));
        if (x >= 1e50) {
            assertFalse(okLive, "live out of range");
            assertEq(live, abi.encodeWithSelector(Exp10FixedOutOfRange.selector, x), "live out of range bytes");
            assertFalse(okLoop, "loop out of range");
        } else {
            assertTrue(okLive, "live in range");
        }
        assertEq(okLive, okLoop, "success");
        assertEq(live, loop, "bytes");
    }

    /// z = |a - b| / (a + b) up to just past `LOG10_RATIO_Z_MAX`, a and b in
    /// [1e75 / 1.002, 1e76].
    function testLog10RatioSeriesLoopEquivalence(uint256 b, uint256 d, bool below) external view {
        b = bound(b, 1e75, 9.9e75);
        d = bound(d, 0, b / 1e6 * 1510);
        checkRatio(below ? b - d : b + d, b);
    }

    /// The reduced gap `log10Reduce` leaves, a within 10^(2^-16) of 1e75.
    function testLog10RatioSeriesLoopEquivalenceReduced(uint256 a) external view {
        a = bound(a, 1e75 - 2, 1000035135277461856608582335861556633189962147970549360011398536055919590052);
        checkRatio(a, 1e75);
    }

    function testLog10RatioSeriesLoopEquivalenceExamples() external view {
        // z = 5.1e-4 exactly, either side.
        checkRatio(500255e70, 499745e70);
        checkRatio(499745e70, 500255e70);
        // The 1.001 edges log10Unrounded hands over.
        checkRatio(1001e72, 1e75);
        // Positive constant.
        // forge-lint: disable-next-line(unsafe-typecast)
        checkRatio(uint256(LOG10_SKIP_BELOW), 1e76);
        checkRatio(1001e73, 1e76);
        checkRatio(1e75 + 1, 1e75);
        checkRatio(1e75, 1e75);
        // z at the guard and one past it, either side.
        checkZ(LOG10_RATIO_Z_MAX, true);
        checkZ(LOG10_RATIO_Z_MAX, false);
        checkZ(LOG10_RATIO_Z_MAX + 1, true);
        checkZ(LOG10_RATIO_Z_MAX + 1, false);
    }

    function testExp10FixedSeriesLoopEquivalence(uint256 x) external view {
        checkExp10(bound(x, 0, 1e50 - 1));
    }

    function testExp10FixedSeriesLoopEquivalenceOutOfRange(uint256 x) external view {
        checkExp10(bound(x, 1e50, type(uint256).max));
    }

    /// Every binary digit set, every one clear, and each alone, with the
    /// largest and smallest remainder below 2^-16.
    function testExp10FixedSeriesLoopEquivalenceExamples() external pure {
        uint256[4] memory xs = [uint256(0), 1e50 - 1, 1.52587890625e45 - 1, 1e50 - 1.52587890625e45];
        for (uint256 i = 0; i < xs.length; i++) {
            assertEq(
                LibDecimalFloatImplementation.exp10Fixed(xs[i]),
                LibDecimalFloatImplementationSeriesLoop.exp10Fixed(xs[i])
            );
        }
        uint256 step = 5e49;
        for (uint256 i = 0; i < 16; i++) {
            for (uint256 r = 0; r < 2; r++) {
                uint256 x = step + r * (1.52587890625e45 - 1);
                assertEq(
                    LibDecimalFloatImplementation.exp10Fixed(x), LibDecimalFloatImplementationSeriesLoop.exp10Fixed(x)
                );
            }
            step /= 2;
        }
    }

    uint256 constant SQRT10 = 316227766016837933199889354443271853371955513932521;

    /// The low word of x * y is below its remainder mod 1e50, so subtracting
    /// the remainder borrows from the high word.
    function borrows(uint256 x, uint256 y) internal pure returns (bool) {
        uint256 low;
        unchecked {
            low = x * y;
        }
        return low < mulmod(x, y, 1e50);
    }

    /// exp10Fixed's series for x below 2^-16, by the general `mulDiv`: the
    /// value multiplied by x before ln 10 is added, and the whole series.
    function exp10Series(uint256 x) internal pure returns (uint256 beforeLn10, uint256 series) {
        uint256[8] memory coefficients = [
            uint256(1959769462647852369682789087147690310674843760584),
            6808936507443706236540404026537606122629959236393,
            20699584869686809669966601589738494188245922773010,
            53938292919558141019969155571017253478007614081814,
            117125514891226696317825761603265234076100689858139,
            203467859229347619683099119171381053024105502647771,
            265094905523919900528083319429700884579872503956640,
            230258509299404568401799145468436420760110148862877
        ];
        series = 501392883377544009807090987164215453583108663277;
        for (uint256 i = 0; i < coefficients.length; i++) {
            if (i == 7) {
                beforeLn10 = series;
            }
            series = coefficients[i] + LibDecimalFloatImplementation.mulDiv(series, x, 1e50);
        }
        series = 1e50 + LibDecimalFloatImplementation.mulDiv(series, x, 1e50);
    }

    /// z = u 1e25 + v at each end of v, across the whole domain of u, and z a
    /// multiple of 2^128, whose square is a multiple of 2^256.
    function testLog10RatioSeriesLoopEquivalenceZSquaredSplit(uint256 u, uint256 k, bool below) external view {
        u = bound(u, 0, LOG10_RATIO_Z_MAX / 1e25 - 1);
        checkZ(u * 1e25, below);
        checkZ(u * 1e25 + 1e25 - 1, below);
        checkZ(bound(k, 1, LOG10_RATIO_Z_MAX >> 128) << 128, below);
    }

    /// The input pair 1e75 ± d with exactly this z.
    function checkZ(uint256 z, bool below) internal view {
        uint256 d = LibDecimalFloatImplementation.mulDiv(2e75, z, below ? 1e50 + z : 1e50 - z);
        while (LibDecimalFloatImplementation.mulDiv(d, 1e50, below ? 2e75 - d : 2e75 + d) < z) {
            d++;
        }
        assertEq(LibDecimalFloatImplementation.mulDiv(d, 1e50, below ? 2e75 - d : 2e75 + d), z, "z");
        checkRatio(below ? 1e75 - d : 1e75 + d, 1e75);
    }

    /// The first step multiplies 1e50 or SQRT10, and neither borrows.
    function testExp10FixedFirstStepNeverBorrows() external pure {
        assertFalse(borrows(1e50, 177827941003892280122542119519268484473579052640225));
        assertFalse(borrows(SQRT10, 177827941003892280122542119519268484473579052640225));
    }

    /// x in [0.5, 0.5 + 2^-16) whose final SQRT10 * series borrows.
    function testExp10FixedSeriesLoopEquivalenceFinalBorrow() external pure {
        uint256[3] memory xs =
            [uint256(87015477053855611590102368556), 129156888290026095774709585062, 430189686290292988458280452418];
        for (uint256 i = 0; i < xs.length; i++) {
            (, uint256 series) = exp10Series(xs[i]);
            assertTrue(borrows(SQRT10, series), "borrows");
            uint256 x = 5e49 + xs[i];
            uint256 result = LibDecimalFloatImplementation.exp10Fixed(x);
            assertEq(result, LibDecimalFloatImplementation.mulDiv(SQRT10, series, 1e50), "mulDiv");
            assertEq(result, LibDecimalFloatImplementationSeriesLoop.exp10Fixed(x), "loop");
        }
    }

    /// x below 2^-16 whose series * x before adding ln 10 borrows.
    function testExp10FixedSeriesLoopEquivalenceLn10StepBorrow() external pure {
        uint256[3] memory xs = [
            uint256(858803594111162378152345370348828441692620967),
            724330556364502386237515770486668923888293239,
            432154281105992271870088449799288377367521809
        ];
        for (uint256 i = 0; i < xs.length; i++) {
            (uint256 beforeLn10, uint256 series) = exp10Series(xs[i]);
            assertTrue(borrows(beforeLn10, xs[i]), "borrows");
            uint256 result = LibDecimalFloatImplementation.exp10Fixed(xs[i]);
            assertEq(result, series, "mulDiv");
            assertEq(result, LibDecimalFloatImplementationSeriesLoop.exp10Fixed(xs[i]), "loop");
        }
    }

    /// The series at x = 2^-16 floors to the last step's constant, so taking
    /// that step at x = 2^-16 or leaving x to the series gives the same result.
    function testExp10FixedLastStepIsSeriesAtItsThreshold() external pure {
        (, uint256 series) = exp10Series(1.52587890625e45);
        assertEq(series, 100003513527746185660858233586155663318996214797054);
    }
}
