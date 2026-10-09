// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, console2} from "forge-std-1.17.0/src/Test.sol";

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {PowNegativeBase} from "src/error/ErrDecimalFloat.sol";
import {LibTestExactDecimal, U512} from "test/lib/LibTestExactDecimal.sol";
import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";

contract LibDecimalFloatSqrtTest is Test {
    using LibDecimalFloat for Float;

    function sqrtExternal(Float a) external pure returns (Float) {
        return a.sqrt();
    }

    function checkSqrt(
        int256 signedCoefficient,
        int256 exponent,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal view {
        Float a = LibDecimalFloat.packLossless(signedCoefficient, exponent);
        uint256 beforeGas = gasleft();
        Float c = a.sqrt();
        uint256 afterGas = gasleft();
        console2.log("Gas used:", beforeGas - afterGas);
        console2.logInt(signedCoefficient);
        console2.logInt(exponent);
        (int256 actualSignedCoefficient, int256 actualExponent) = c.unpack();
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signedCoefficient");
        assertEq(actualExponent, expectedExponent, "exponent");
    }

    /// The root r is under 5e-41 relative from sqrt a, so r^2 is strictly
    /// between a (1 - 5e-41)^2 and a (1 + 5e-41)^2. Scaled by 1e82 and
    /// compared exactly: c^2 10^(2e + 82) against A (1e41 +- 5)^2 10^f.
    function checkRoundTrip(int256 signedCoefficient, int256 exponent) internal pure {
        (int256 c, int256 e) = LibDecimalFloat.packLossless(signedCoefficient, exponent).sqrt().unpack();
        // forge-lint: disable-next-line(unsafe-typecast)
        U512 memory square = LibTestExactDecimal.mul(uint256(c), uint256(c));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 a = uint256(signedCoefficient);
        U512 memory upper = LibTestExactDecimal.mulSmall(LibTestExactDecimal.mul(a, 1e41 + 5), 1e41 + 5);
        U512 memory lower = LibTestExactDecimal.mulSmall(LibTestExactDecimal.mul(a, 1e41 - 5), 1e41 - 5);
        assertLt(LibTestExactDecimal.cmpScaled(square, 2 * e + 82, upper, exponent), 0, "round trip above");
        assertGt(LibTestExactDecimal.cmpScaled(square, 2 * e + 82, lower, exponent), 0, "round trip below");
    }

    function testSqrt() external view {
        checkSqrt(0, 0, 0, 0);
        checkSqrt(2, 0, 14142135623730950488016887242096980785697, -40);
        checkSqrt(4, 0, 2e40, -40);
        checkSqrt(16, 0, 4e40, -40);
    }

    function checkSqrtExact(
        int256 signedCoefficient,
        int256 exponent,
        int256 rootSignedCoefficient,
        int256 rootExponent
    ) internal pure {
        Float c = LibDecimalFloat.packLossless(signedCoefficient, exponent).sqrt();
        assertTrue(c.eq(LibDecimalFloat.packLossless(rootSignedCoefficient, rootExponent)), "exact");
    }

    function testSqrtExact() external pure {
        checkSqrtExact(1, 0, 1, 0);
        checkSqrtExact(4, 0, 2, 0);
        checkSqrtExact(9, 0, 3, 0);
        checkSqrtExact(16, 0, 4, 0);
        checkSqrtExact(25, 0, 5, 0);
        checkSqrtExact(100, 0, 10, 0);
        checkSqrtExact(144, 0, 12, 0);
        checkSqrtExact(10000, 0, 100, 0);
        checkSqrtExact(1e6, 0, 1e3, 0);
        checkSqrtExact(25, -2, 5, -1);
        checkSqrtExact(1, -2, 1, -1);
        checkSqrtExact(225, -2, 15, -1);
        checkSqrtExact(152399025, 0, 12345, 0);
        checkSqrtExact(1524157875019052100, -18, 12345678900, -10);
    }

    function testSqrtNegative(Float a) external {
        // We can't simply minus 0 to get a negative base.
        (int256 signedCoefficient, int256 exponent) = a.unpack();
        vm.assume(signedCoefficient != 0);
        if (signedCoefficient > 0) {
            // A positive int224 coefficient negates exactly.
            signedCoefficient = -signedCoefficient;
            a = LibDecimalFloat.packLossless(signedCoefficient, exponent);
        }

        vm.expectRevert(abi.encodeWithSelector(PowNegativeBase.selector, signedCoefficient, exponent));
        this.sqrtExternal(a);
    }

    function testSqrtRoundTrip() external pure {
        checkRoundTrip(2, 0);
        checkRoundTrip(4, 0);
        checkRoundTrip(16, 0);
        checkRoundTrip(25, 0);
        checkRoundTrip(100, 0);
        checkRoundTrip(10000, 0);
        checkRoundTrip(1000000, 0);
        checkRoundTrip(100000000, 0);
    }

    function testRoundTripFuzzSqrt(int224 signedCoefficient, int32 exponent) external pure {
        signedCoefficient = int224(bound(signedCoefficient, 1, type(int224).max));
        exponent = int32(bound(exponent, -1e9, 1e9));
        checkRoundTrip(signedCoefficient, exponent);
    }

    /// sqrt(n^2 10^(2k)) is n 10^k exactly for n below 1e20, whose root has
    /// fewer than the 41 digits pow keeps.
    function testSqrtExactSquares(uint256 n, int256 k) external pure {
        n = bound(n, 1, 1e20 - 1);
        k = bound(k, -1e9, 1e9);
        // forge-lint: disable-next-line(unsafe-typecast)
        Float root = LibDecimalFloat.packLossless(int256(n * n), 2 * k).sqrt();
        // forge-lint: disable-next-line(unsafe-typecast)
        assertTrue(root.eq(LibDecimalFloat.packLossless(int256(n), k)), "exact");
    }

    /// sqrt(x 100^k) is sqrt(x) 10^k exactly, as log10 sums the characteristic
    /// as an integer. x stays away from 1, where log10 keeps digits that a
    /// shift truncates.
    function testSqrtDecadeShift(int256 signedCoefficient, int256 exponent, int256 shift, bool small) external pure {
        signedCoefficient = bound(signedCoefficient, 1, type(int224).max);
        if (small) {
            exponent = bound(exponent, -1e9, -100);
            shift = bound(shift, -5e8, 0);
        } else {
            exponent = bound(exponent, 1, 1e9);
            shift = bound(shift, 0, 5e8);
        }
        (int256 rootCoefficient, int256 rootExponent) =
            LibDecimalFloat.packLossless(signedCoefficient, exponent).sqrt().unpack();
        (int256 shiftedCoefficient, int256 shiftedExponent) =
            LibDecimalFloat.packLossless(signedCoefficient, exponent + 2 * shift).sqrt().unpack();
        assertTrue(
            LibTestExactDecimal.eq(shiftedCoefficient, shiftedExponent, rootCoefficient, rootExponent + shift), "shift"
        );
    }

    /// floor(sqrt n) for n in [1e80, 1e82), by bisection on exact squares.
    function floorRoot(U512 memory n) internal pure returns (uint256) {
        uint256 low = 1e40;
        uint256 high = 1e41;
        while (high - low > 1) {
            uint256 mid = (low + high) / 2;
            if (LibTestExactDecimal.cmp(LibTestExactDecimal.mul(mid, mid), n) <= 0) {
                low = mid;
            } else {
                high = mid;
            }
        }
        return low;
    }

    /// a = A 10^f with A in [1e75, 1e76) is N 10^(f - s) for N = A 10^s with
    /// s 5 or 6 making f - s even, so sqrt a is sqrt N 10^((f - s) / 2) with
    /// sqrt N in [1e40, 1e41). Its 41 digit rounding is the integer nearest
    /// sqrt N: r + 1 for r = floor(sqrt N) when N > (r + 1/2)^2, which for
    /// integers is N > r^2 + r, else r.
    function testSqrtReferenceFuzz(int256 signedCoefficient, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, 1, type(int224).max);
        exponent = bound(exponent, -1e9, 1e9);
        (int256 rootCoefficient, int256 rootExponent) =
            LibDecimalFloat.packLossless(signedCoefficient, exponent).sqrt().unpack();
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 a = uint256(signedCoefficient);
        while (a < 1e75) {
            a *= 10;
            exponent -= 1;
        }
        uint256 s = exponent % 2 == 0 ? 6 : 5;
        U512 memory n = LibTestExactDecimal.mulPow10(LibTestExactDecimal.u512(a), s);
        uint256 r = floorRoot(n);
        U512 memory midpointFloor = LibTestExactDecimal.add(LibTestExactDecimal.mul(r, r), LibTestExactDecimal.u512(r));
        if (LibTestExactDecimal.cmp(n, midpointFloor) > 0) {
            r += 1;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expectedCoefficient = int256(r);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expectedExponent = (exponent - int256(s)) / 2;
        assertTrue(
            LibTestExactDecimal.eq(rootCoefficient, rootExponent, expectedCoefficient, expectedExponent), "reference"
        );
    }

    /// x < y implies sqrt(x) <= sqrt(y), down to adjacent coefficients.
    function testSqrtMonotone(int256 signedCoefficient, int256 gap, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, 1, type(int224).max - 1e3);
        gap = bound(gap, 1, 1e3);
        exponent = bound(exponent, -1e9, 1e9);
        Float low = LibDecimalFloat.packLossless(signedCoefficient, exponent).sqrt();
        Float high = LibDecimalFloat.packLossless(signedCoefficient + gap, exponent).sqrt();
        assertTrue(low.lte(high), "monotone");
    }

    /// x 10^d > m^2 in 512 bits, for x 10^d below 2^256 squared.
    function past(uint256 x, uint256 d, uint256 m) internal pure returns (bool) {
        (uint256 xHigh, uint256 xLow) = Math.mul512(x, 10 ** d);
        (uint256 mHigh, uint256 mLow) = Math.mul512(m, m);
        return xHigh > mHigh || (xHigh == mHigh && xLow > mLow);
    }

    /// The root c 10^e of a, c in [1e40, 1e41), is correctly rounded exactly
    /// when (c - 1/2)^2 10^2e < a < (c + 1/2)^2 10^2e, with the lower midpoint
    /// at c = 1e40 a twentieth of a unit below. With a = A 10^f for A in
    /// [1e75, 1e76) both compare 4 A 10^(f - 2e) against (2c +- 1)^2.
    function assertCorrectlyRounded(int256 signedCoefficient, int256 exponent, Float root) internal pure {
        (int256 c, int256 e) = root.unpack();
        while (c < 1e40) {
            c *= 10;
            e -= 1;
        }
        while (c >= 1e41) {
            assertEq(c % 10, 0, "root digits");
            c /= 10;
            e += 1;
        }
        while (signedCoefficient < 1e75) {
            signedCoefficient *= 10;
            exponent -= 1;
        }
        int256 d = exponent - 2 * e;
        assertTrue(d >= 4 && d <= 7, "root scale");
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 x = uint256(signedCoefficient) * 4;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 m = uint256(2 * c);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertFalse(past(x, uint256(d), m + 1), "above upper midpoint");
        if (c == 1e40) {
            // forge-lint: disable-next-line(unsafe-typecast)
            assertTrue(past(x, uint256(d + 2), 2e41 - 1), "below lower midpoint");
        } else {
            // forge-lint: disable-next-line(unsafe-typecast)
            assertTrue(past(x, uint256(d), m - 1), "below lower midpoint");
        }
    }

    function testSqrtCorrectlyRoundedFuzz(int256 signedCoefficient, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, 1, type(int224).max);
        exponent = bound(exponent, -1e9, 1e9);
        Float root = LibDecimalFloat.packLossless(signedCoefficient, exponent).sqrt();
        assertCorrectlyRounded(signedCoefficient, exponent, root);
    }

    /// A = floor((c + 1/2)^2 / 1e16) has a root within 5e-25 of a unit below
    /// the midpoint (c + 1/2) 1e-8, and A + 1 a root above it, far inside
    /// pow's 3.6e-8 of a unit, so only the midpoint comparison rounds them:
    /// to c and to c + 1. 100^k scales the root by 10^k exactly.
    function checkMidpoint(uint256 c, int256 k) internal pure {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 a = int256(Math.mulDiv(2 * c + 1, 2 * c + 1, 4e16));
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedC = int256(c);
        assertTrue(
            LibDecimalFloat.packLossless(a, 2 * k).sqrt().eq(LibDecimalFloat.packLossless(signedC, k - 8)),
            "below midpoint"
        );
        assertTrue(
            LibDecimalFloat.packLossless(a + 1, 2 * k).sqrt().eq(LibDecimalFloat.packLossless(signedC + 1, k - 8)),
            "above midpoint"
        );
        assertCorrectlyRounded(a, 2 * k, LibDecimalFloat.packLossless(a, 2 * k).sqrt());
        assertCorrectlyRounded(a + 1, 2 * k, LibDecimalFloat.packLossless(a + 1, 2 * k).sqrt());
    }

    /// The ends of the decade. At 1e41 - 1 the upper neighbour is 1e40 a
    /// decade up, so a root that pow rounds to 1e40 is checked against the
    /// midpoint 1e41 - 1/2 below it.
    function testSqrtMidpointEnds() external pure {
        checkMidpoint(1e40, 0);
        checkMidpoint(1e41 - 1, 0);
        checkMidpoint(1e41 - 1, -3);
        checkMidpoint(1e40, 5);
    }

    /// m = 2c + 1 is the first odd m past sqrt(100007 2^256), with m^2 under
    /// m / 4 past 100007 2^256. a = (c + 1/4)^2 floored to 67 digits has 4a
    /// 10^k under m^2 by about 2c, so below 100007 2^256: the high words of
    /// 4a 10^k and m^2 differ while 4a's low word is the larger.
    function testSqrtMidpointStraddlesWord() external pure {
        uint256 c = 53805249438034112592410659411875078206494;
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 a = int256(Math.mulDiv(4 * c + 1, 4 * c + 1, 16e15));
        (uint256 mHigh, uint256 mLow) = Math.mul512(2 * c + 1, 2 * c + 1);
        // forge-lint: disable-next-line(unsafe-typecast)
        (uint256 xHigh, uint256 xLow) = Math.mul512(uint256(a) * 4, 1e15);
        assertEq(mHigh, 100007, "m high");
        assertEq(xHigh, 100006, "x high");
        assertGt(xLow, mLow, "low words");
        Float root = LibDecimalFloat.packLossless(a, 15).sqrt();
        // forge-lint: disable-next-line(unsafe-typecast)
        assertTrue(root.eq(LibDecimalFloat.packLossless(int256(c), 0)), "root");
        assertCorrectlyRounded(a, 15, root);
    }

    function testSqrtMidpointFuzz(uint256 c, int256 k) external pure {
        c = bound(c, 1e40, 1e41 - 1);
        k = bound(k, -5e8, 5e8);
        checkMidpoint(c, k);
    }
}
