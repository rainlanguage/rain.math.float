// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    LibDecimalFloatImplementation,
    LOG10_RATIO_Z_MAX,
    POW_FIXED_LN10
} from "../../../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Log10RatioOutOfRange} from "../../../../src/error/ErrDecimalFloat.sol";
import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";

/// log10Ratio against its documented floors, each taken by OpenZeppelin's
/// 512-bit mulDiv: floor(z^2 / 1e50), each next power floored the same way,
/// and, when relative, the difference scaled by the largest power of ten that
/// keeps it within int256.max.
contract LibDecimalFloatImplementationLog10RatioFloorsTest is Test {
    function ratio(uint256 a, uint256 b, bool relative) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.log10Ratio(a, b, relative);
    }

    function expectedRatio(uint256 a, uint256 b, bool relative) internal pure returns (int256, int256) {
        uint256 difference = a < b ? b - a : a - b;
        uint256 sum = a + b;
        uint256 z = Math.mulDiv(difference, 1e50, sum);
        uint256 zSquared = Math.mulDiv(z, z, 1e50);
        uint256 series = 1e50 + zSquared / 3;
        uint256 term = Math.mulDiv(zSquared, zSquared, 1e50);
        series += term / 5;
        for (uint256 k = 7; k <= 15; k += 2) {
            term = Math.mulDiv(term, zSquared, 1e50);
            series += term / k;
        }
        int256 exponent = -50;
        if (relative && difference != 0) {
            while (difference <= uint256(type(int256).max) / 10) {
                difference *= 10;
                exponent -= 1;
            }
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 coefficient = int256(Math.mulDiv(difference, Math.mulDiv(series, 2e50, POW_FIXED_LN10), sum));
        return (a < b ? -coefficient : coefficient, exponent);
    }

    function check(uint256 a, uint256 b, bool relative) internal pure {
        (int256 expectedCoefficient, int256 expectedExponent) = expectedRatio(a, b, relative);
        (int256 coefficient, int256 exponent) = LibDecimalFloatImplementation.log10Ratio(a, b, relative);
        assertEq(coefficient, expectedCoefficient, "coefficient");
        assertEq(exponent, expectedExponent, "exponent");
    }

    /// x^2 / 1e50 floored without the v^2 of x = u 1e25 + v, the term the
    /// 1e25 split adds back.
    function floorWithoutLowSquare(uint256 x) internal pure returns (uint256) {
        uint256 u = x / 1e25;
        uint256 v = x % 1e25;
        return u * u + (2e25 * u * v) / 1e50;
    }

    function testLog10RatioMatchesDocumentedFloors(uint256 b, uint256 d, bool below, bool relative) external pure {
        b = bound(b, 1e50, 1e76);
        d = bound(d, 0, b / 1000);
        check(below ? b - d : b + d, b, relative);
    }

    /// Differences at int256.max / 10^j and its neighbours, the edges of every
    /// scaling step that an in-range z can reach.
    function testLog10RatioRelativeScalingEdges() external pure {
        uint256 maxInt = uint256(type(int256).max);
        for (uint256 j = 4; j <= 76; j++) {
            uint256 t = maxInt / 10 ** j;
            uint256[3] memory ds = [t - 1, t, t + 1];
            for (uint256 i = 0; i < 3; i++) {
                check(1e76 + ds[i], 1e76, true);
                check(1e76, 1e76 + ds[i], true);
            }
        }
    }

    /// a + b of 1e50 makes z = a - b, at z where the v^2 term changes
    /// floor(z^2 / 1e50).
    function testLog10RatioZSquaredSplitFloor() external pure {
        uint256[3] memory zs = [
            uint256(56883319544067350827351642713035170660395976418),
            69250189211361762299573138366807705404349976690,
            67050331744923857944018816904372368570385629146
        ];
        for (uint256 i = 0; i < zs.length; i++) {
            uint256 z = zs[i];
            assertTrue(Math.mulDiv(z, z, 1e50) != floorWithoutLowSquare(z), "v^2 changes the floor");
            check((1e50 + z) / 2, (1e50 - z) / 2, true);
            check((1e50 - z) / 2, (1e50 + z) / 2, true);
        }
    }

    /// As above, where the v^2 term changes floor(zSquared^2 / 1e50).
    function testLog10RatioZFourthSplitFloor() external pure {
        uint256[3] memory zs = [
            uint256(73775551262589173786226722879626892701410179108),
            42188508030073509007227429297983227555291873818,
            44929879154328332185903286926556476011846575532
        ];
        for (uint256 i = 0; i < zs.length; i++) {
            uint256 zSquared = Math.mulDiv(zs[i], zs[i], 1e50);
            assertTrue(
                Math.mulDiv(zSquared, zSquared, 1e50) != floorWithoutLowSquare(zSquared), "v^2 changes the floor"
            );
            check((1e50 + zs[i]) / 2, (1e50 - zs[i]) / 2, true);
            check((1e50 - zs[i]) / 2, (1e50 + zs[i]) / 2, true);
        }
    }

    /// The 1e2 and 10 steps see a difference at their bound only unscaled, as
    /// int256.max / 1e2 and / 10 are not multiples of 10. Each such difference
    /// at the largest a + b in a word has z past LOG10_RATIO_Z_MAX, and z only
    /// grows as a + b falls, so it reverts before the cascade.
    function testLog10RatioLastScalingBoundsUnreachable() external {
        uint256[2] memory ds = [uint256(type(int256).max) / 1e2, uint256(type(int256).max) / 10];
        for (uint256 i = 0; i < ds.length; i++) {
            uint256 d = ds[i];
            assertTrue(d % 10 != 0, "not a multiple of 10");
            uint256 sum = type(uint256).max - ((type(uint256).max - d) % 2);
            uint256 a = sum - (sum - d) / 2;
            uint256 b = (sum - d) / 2;
            assertEq(a - b, d, "difference");
            assertTrue(Math.mulDiv(d, 1e50, sum) > LOG10_RATIO_Z_MAX, "z past max");
            vm.expectRevert(abi.encodeWithSelector(Log10RatioOutOfRange.selector, a, b));
            this.ratio(a, b, true);
        }
    }
}
