// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibDecimalFloatImplementationLog10RatioPr336} from "test/lib/LibDecimalFloatImplementationLog10RatioPr336.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";

/// `log10Ratio` returns and reverts the same bytes as the #336 head it was
/// restructured from, wherever a - b fits in int256, which #336 cast it to.
/// a and b are kept within a factor 100 of each other, as the series loop runs
/// about 1e50 times as z nears 1.
contract LibDecimalFloatImplementationLog10RatioPr336EquivalenceTest is Test {
    function pr336Ratio(uint256 a, uint256 b, bool relative) external pure returns (int256, int256) {
        return LibDecimalFloatImplementationLog10RatioPr336.log10Ratio(a, b, relative);
    }

    function liveRatio(uint256 a, uint256 b, bool relative) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.log10Ratio(a, b, relative);
    }

    function checkSame(uint256 a, uint256 b, bool relative) internal view {
        (bool okPr336, bytes memory pr336) = address(this).staticcall(abi.encodeCall(this.pr336Ratio, (a, b, relative)));
        (bool okLive, bytes memory live) = address(this).staticcall(abi.encodeCall(this.liveRatio, (a, b, relative)));
        assertEq(okLive, okPr336, "success");
        assertEq(live, pr336, "bytes");
    }

    function near(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 maxInt = uint256(type(int256).max);
        uint256 low = b / 100;
        if (b > maxInt && b - maxInt > low) {
            low = b - maxInt;
        }
        uint256 high = b > type(uint256).max / 100 ? type(uint256).max : b * 100;
        if (b < type(uint256).max - maxInt && b + maxInt < high) {
            high = b + maxInt;
        }
        return bound(a, low, high);
    }

    function testLog10RatioPr336EquivalenceAny(uint256 a, uint256 b, bool relative) external view {
        checkSame(near(a, b), b, relative);
    }

    /// a and b at most 1e76, the stated domain.
    function testLog10RatioPr336EquivalenceDomain(uint256 a, uint256 b, bool relative) external view {
        b = bound(b, 0, 1e76);
        a = bound(a, b / 100, b > 1e74 ? 1e76 : b * 100);
        checkSame(a, b, relative);
    }

    /// b a power of ten and a within 1.0183e-3 of it, as `log10Unrounded`
    /// hands over, with the difference at every magnitude.
    function testLog10RatioPr336EquivalenceNear(uint256 b, uint256 d, uint256 digits, bool below) external view {
        b = 10 ** bound(b, 0, 76);
        d = bound(d, 0, 10 ** bound(digits, 0, 76));
        d = bound(d, 0, b / 982);
        checkSame(below ? b - d : b + d, b, true);
    }

    /// Differences at 10^k - 1, 10^k and 10^k + 1, and at int256.max / 10^k
    /// and its neighbours, the edges of every scaling step.
    function testLog10RatioPr336EquivalenceEdges() external view {
        uint256 maxInt = uint256(type(int256).max);
        for (uint256 k = 0; k <= 76; k++) {
            uint256 p = 10 ** k;
            uint256 t = maxInt / p;
            uint256[6] memory ds = [p - 1, p, p + 1, t - 1, t, t + 1];
            for (uint256 i = 0; i < 6; i++) {
                uint256 d = ds[i];
                checkSame(1e76 + d, 1e76, true);
                checkSame(1e76, 1e76 + d, true);
                if (d <= maxInt) {
                    checkSame(2 * d, d, true);
                    checkSame(d, 2 * d, true);
                }
                if (d <= 5e75) {
                    checkSame(1e76 - d, 1e76, true);
                }
            }
        }
    }
}
