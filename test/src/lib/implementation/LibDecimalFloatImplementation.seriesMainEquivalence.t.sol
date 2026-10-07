// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibDecimalFloatImplementationSeriesMain} from "test/lib/LibDecimalFloatImplementationSeriesMain.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";

/// `log10Ratio` and `exp10Fixed` return exactly what they returned before
/// their multiplies were written out in place, over the domain each documents.
contract LibDecimalFloatImplementationSeriesMainEquivalenceTest is Test {
    function checkRatio(uint256 a, uint256 b) internal pure {
        for (uint256 i = 0; i < 2; i++) {
            (int256 liveCoefficient, int256 liveExponent) = LibDecimalFloatImplementation.log10Ratio(a, b, i == 0);
            (int256 mainCoefficient, int256 mainExponent) =
                LibDecimalFloatImplementationSeriesMain.log10Ratio(a, b, i == 0);
            assertEq(liveCoefficient, mainCoefficient, "coefficient");
            assertEq(liveExponent, mainExponent, "exponent");
        }
    }

    /// z = |a - b| / (a + b) up to 5.1e-4, a and b in [1e75 / 1.002, 1e76].
    function testLog10RatioSeriesMainEquivalence(uint256 b, uint256 d, bool below) external pure {
        b = bound(b, 1e75, 9.9e75);
        d = bound(d, 0, b / 1e6 * (below ? 1019 : 1020));
        checkRatio(below ? b - d : b + d, b);
    }

    /// The reduced gap `log10Reduce` leaves, a within 10^(2^-16) of 1e75.
    function testLog10RatioSeriesMainEquivalenceReduced(uint256 a) external pure {
        a = bound(a, 1e75 - 2, 1000035135277461856608582335861556633189962147970549360011398536055919590052);
        checkRatio(a, 1e75);
    }

    function testLog10RatioSeriesMainEquivalenceExamples() external pure {
        // z = 5.1e-4 exactly, either side.
        checkRatio(500255e70, 499745e70);
        checkRatio(499745e70, 500255e70);
        // The 1.001 edges log10Unrounded hands over.
        checkRatio(1001e72 - 1, 1e75);
        checkRatio(9999e72, 1e76);
        checkRatio(1e75 + 1, 1e75);
        checkRatio(1e75, 1e75);
    }

    function testExp10FixedSeriesMainEquivalence(uint256 x) external pure {
        x = bound(x, 0, 1e50 - 1);
        assertEq(LibDecimalFloatImplementation.exp10Fixed(x), LibDecimalFloatImplementationSeriesMain.exp10Fixed(x));
    }

    /// Every binary digit set, every one clear, and each alone, with the
    /// largest and smallest remainder below 2^-16.
    function testExp10FixedSeriesMainEquivalenceExamples() external pure {
        uint256[4] memory xs = [uint256(0), 1e50 - 1, 1.52587890625e45 - 1, 1e50 - 1.52587890625e45];
        for (uint256 i = 0; i < xs.length; i++) {
            assertEq(
                LibDecimalFloatImplementation.exp10Fixed(xs[i]),
                LibDecimalFloatImplementationSeriesMain.exp10Fixed(xs[i])
            );
        }
        uint256 step = 5e49;
        for (uint256 i = 0; i < 16; i++) {
            for (uint256 r = 0; r < 2; r++) {
                uint256 x = step + r * (1.52587890625e45 - 1);
                assertEq(
                    LibDecimalFloatImplementation.exp10Fixed(x), LibDecimalFloatImplementationSeriesMain.exp10Fixed(x)
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

    /// z a multiple of 2^128 squares to a multiple of 2^256, so z^2 borrows.
    function testLog10RatioSeriesMainEquivalenceZSquaredBorrow(uint256 k, bool below) external pure {
        k = bound(k, 1, 1e6);
        uint256 z = k << 128;
        assertTrue(borrows(z, z), "borrows");
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
    function testExp10FixedSeriesMainEquivalenceFinalBorrow() external pure {
        uint256[3] memory xs =
            [uint256(87015477053855611590102368556), 129156888290026095774709585062, 430189686290292988458280452418];
        for (uint256 i = 0; i < xs.length; i++) {
            (, uint256 series) = exp10Series(xs[i]);
            assertTrue(borrows(SQRT10, series), "borrows");
            uint256 x = 5e49 + xs[i];
            uint256 result = LibDecimalFloatImplementation.exp10Fixed(x);
            assertEq(result, LibDecimalFloatImplementation.mulDiv(SQRT10, series, 1e50), "mulDiv");
            assertEq(result, LibDecimalFloatImplementationSeriesMain.exp10Fixed(x), "main");
        }
    }

    /// x below 2^-16 whose series * x before adding ln 10 borrows.
    function testExp10FixedSeriesMainEquivalenceLn10StepBorrow() external pure {
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
            assertEq(result, LibDecimalFloatImplementationSeriesMain.exp10Fixed(xs[i]), "main");
        }
    }

    /// The series at x = 2^-16 floors to the last step's constant, so taking
    /// that step at x = 2^-16 or leaving x to the series gives the same result.
    function testExp10FixedLastStepIsSeriesAtItsThreshold() external pure {
        (, uint256 series) = exp10Series(1.52587890625e45);
        assertEq(series, 100003513527746185660858233586155663318996214797054);
    }
}
