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
}
