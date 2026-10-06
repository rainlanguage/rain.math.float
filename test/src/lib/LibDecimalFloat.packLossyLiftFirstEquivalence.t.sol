// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatPackLossyLiftFirst} from "test/lib/LibDecimalFloatPackLossyLiftFirst.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";

/// `packLossy` returns and reverts the same bytes as the lift-first version
/// for every input.
contract LibDecimalFloatPackLossyLiftFirstEquivalenceTest is Test {
    function liftFirstPackLossy(int256 c, int256 e) external pure returns (Float, bool) {
        return LibDecimalFloatPackLossyLiftFirst.packLossy(c, e);
    }

    function packLossy(int256 c, int256 e) external pure returns (Float, bool) {
        return LibDecimalFloat.packLossy(c, e);
    }

    function check(int256 c, int256 e) internal view {
        (bool expectedSuccess, bytes memory expected) =
            address(this).staticcall(abi.encodeCall(this.liftFirstPackLossy, (c, e)));
        (bool success, bytes memory actual) = address(this).staticcall(abi.encodeCall(this.packLossy, (c, e)));
        assertEq(success, expectedSuccess, "success");
        assertEq(actual, expected, "bytes");
    }

    function testPackLossyLiftFirstEquivalence(int256 c, int256 e) external view {
        check(c, e);
    }

    /// Exponents either side of the ceiling, past the 67 digit headroom.
    function testPackLossyLiftFirstEquivalenceCeilBand(int256 c, int256 offset) external view {
        offset = bound(offset, -80, 80);
        check(c, int256(type(int32).max) + offset);
    }

    /// Coefficients at the headroom edge of every lift, either side of the
    /// int224 bounds divided by the scale.
    function testPackLossyLiftFirstEquivalenceHeadroomEdge(uint256 excess, int256 delta, bool negative) external view {
        excess = bound(excess, 0, 70);
        delta = bound(delta, -3, 3);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 scale = int256(10 ** excess);
        int256 edge = (negative ? int256(type(int224).min) : int256(type(int224).max)) / scale;
        // forge-lint: disable-next-line(unsafe-typecast)
        check(edge + delta, int256(type(int32).max) + int256(excess));
    }

    /// Coefficients that must shed, with exponents where shedding meets the
    /// ceiling or wraps through int256.max.
    function testPackLossyLiftFirstEquivalenceShedAtTheEdges(int256 c, int256 offset, bool top) external view {
        // forge-lint: disable-next-line(unsafe-typecast)
        if (int224(c) == c) {
            c = c >= 0 ? int256(type(int224).max) + 1 + c % 1e60 : int256(type(int224).min) - 1 + c % 1e60;
        }
        offset = bound(offset, 0, 30);
        int256 e = top ? type(int256).max - offset : int256(type(int32).max) - 15 + offset;
        check(c, e);
    }

    /// Unbounded exponents with int224 coefficients, the packed path.
    function testPackLossyLiftFirstEquivalencePacked(int224 c, int256 e) external view {
        check(c, e);
    }

    function testPackLossyLiftFirstEquivalenceExtremes() external view {
        int256[8] memory cs = [
            type(int256).min,
            type(int256).max,
            int256(type(int224).min),
            int256(type(int224).max),
            int256(type(int224).min) - 1,
            int256(type(int224).max) + 1,
            int256(1),
            int256(-1)
        ];
        int256[8] memory es = [
            type(int256).min,
            type(int256).max,
            type(int256).max - 9,
            type(int256).max - 10,
            int256(type(int32).max),
            int256(type(int32).max) + 1,
            int256(type(int32).max) + 67,
            int256(type(int32).max) + 68
        ];
        for (uint256 i = 0; i < cs.length; i++) {
            for (uint256 j = 0; j < es.length; j++) {
                check(cs[i], es[j]);
            }
        }
    }
}
