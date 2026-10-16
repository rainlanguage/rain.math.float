// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {console2} from "forge-std-1.17.0/src/Test.sol";

import {LibDecimalFloat, Float} from "../../../src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "../../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {PowNegativeBase, ExponentOverflow, SqrtOutOfRange} from "../../../src/error/ErrDecimalFloat.sol";
import {LibTestErrorBound} from "../../lib/LibTestErrorBound.sol";
import {LibExactFloat, U512} from "../../lib/LibExactFloat.sol";
import {LibDecimalFloatSqrtVariants} from "../../lib/LibDecimalFloatSqrtVariants.sol";
import {SqrtCorrectlyRoundedTest} from "../../abstract/SqrtCorrectlyRoundedTest.sol";
import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";

contract LibDecimalFloatSqrtTest is SqrtCorrectlyRoundedTest {
    using LibDecimalFloat for Float;

    /// The root is within E of sqrt a and its square, rounded, within E2 of
    /// the root squared, so a over the square is within L = 2E + E2 of 1,
    /// plus higher orders under 1e-79 and the quotient's truncation under
    /// 1e-74. For a square `t` that pow is within E2 t + u of, with u the
    /// floor's 1e-2147483648, a - t is within L (t + u) + u, so a / t - 1 is
    /// within L (1 + F) + F for F = u / t.
    function diffLimit(Float root, int256 roundTripCoefficient, int256 roundTripExponent)
        internal
        pure
        returns (int256, int256)
    {
        (int256 errorCoefficient, int256 errorExponent) = LibTestErrorBound.sqrt().unpack();
        (int256 limitCoefficient, int256 limitExponent) =
            LibTestErrorBound.pow(root, LibDecimalFloat.FLOAT_TWO).unpack();
        (, limitCoefficient, limitExponent) =
            LibExactFloat.addPartsWide(limitCoefficient, limitExponent, 2 * errorCoefficient, errorExponent);
        (, limitCoefficient, limitExponent) = LibExactFloat.addPartsWide(limitCoefficient, limitExponent, 100001, -79);
        (int256 floorCoefficient, int256 floorExponent) =
            LibTestErrorBound.floor(roundTripCoefficient, roundTripExponent).unpack();
        if (floorCoefficient == 0) {
            return (limitCoefficient, limitExponent);
        }
        (int256 crossCoefficient, int256 crossExponent) =
            LibExactFloat.mulPayload(limitCoefficient, limitExponent, floorCoefficient, floorExponent);
        (, crossCoefficient, crossExponent) =
            LibExactFloat.addPartsWide(crossCoefficient, crossExponent, floorCoefficient, floorExponent);
        (, limitCoefficient, limitExponent) =
            LibExactFloat.addPartsWide(limitCoefficient, limitExponent, crossCoefficient, crossExponent);
        return (limitCoefficient, limitExponent);
    }

    function sqrtExternal(Float a) external pure returns (Float) {
        return a.sqrt();
    }

    function powExternal(Float a, Float b) external pure returns (Float) {
        return a.pow(b);
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
    /// And the root squared by `pow` is within `diffLimit` of a, or, where the
    /// exact square is past every Float, `pow` reverts `ExponentOverflow`
    /// with the root. The square has at most 82 digits, so the 76 `pow`
    /// keeps reach below `10^int32.max` and its floor there is the exact one.
    function checkRoundTrip(int256 signedCoefficient, int256 exponent) internal {
        (int256 c, int256 e) = LibDecimalFloat.packLossless(signedCoefficient, exponent).sqrt().unpack();
        // forge-lint: disable-next-line(unsafe-typecast)
        U512 memory square = LibExactFloat.mul(uint256(c), uint256(c));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 a = uint256(signedCoefficient);
        U512 memory upper = LibExactFloat.mulSmall(LibExactFloat.mul(a, 1e41 + 5), 1e41 + 5);
        U512 memory lower = LibExactFloat.mulSmall(LibExactFloat.mul(a, 1e41 - 5), 1e41 - 5);
        assertLt(LibExactFloat.cmpScaled(square, 2 * e + 82, upper, exponent), 0, "round trip above");
        assertGt(LibExactFloat.cmpScaled(square, 2 * e + 82, lower, exponent), 0, "round trip below");
        if (LibExactFloat.mulOverflows(c, e, c, e)) {
            vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, c, e));
            this.powExternal(LibDecimalFloat.packLossless(c, e), LibDecimalFloat.FLOAT_TWO);
            return;
        }
        (int256 roundTripCoefficient, int256 roundTripExponent) =
            LibDecimalFloat.packLossless(c, e).pow(LibDecimalFloat.FLOAT_TWO).unpack();
        (int256 diffCoefficient, int256 diffExponent) =
            LibExactFloat.quotient(signedCoefficient, exponent, roundTripCoefficient, roundTripExponent);
        (, diffCoefficient, diffExponent) = LibExactFloat.addPartsWide(diffCoefficient, diffExponent, -1, 0);
        (int256 limitCoefficient, int256 limitExponent) =
            diffLimit(LibDecimalFloat.packLossless(c, e), roundTripCoefficient, roundTripExponent);
        assertTrue(
            LibExactFloat.cmpScaled(
                LibExactFloat.u512(LibExactFloat.abs(diffCoefficient)),
                diffExponent,
                LibExactFloat.u512(LibExactFloat.abs(limitCoefficient)),
                limitExponent
            ) <= 0,
            "Round trip sqrt diff too high"
        );
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

    function testSqrtRoundTrip() external {
        checkRoundTrip(2, 0);
        checkRoundTrip(4, 0);
        checkRoundTrip(16, 0);
        checkRoundTrip(25, 0);
        checkRoundTrip(100, 0);
        checkRoundTrip(10000, 0);
        checkRoundTrip(1000000, 0);
        checkRoundTrip(100000000, 0);
        checkRoundTrip(3, -2147483645);
    }

    /// The largest Float's root rounds up, so its square is past every Float.
    function testSqrtRoundTripLargestFloat() external {
        (int256 c, int256 e) = LibDecimalFloat.packLossless(type(int224).max, type(int32).max).sqrt().unpack();
        assertTrue(LibExactFloat.mulOverflows(c, e, c, e), "square overflows");
        checkRoundTrip(type(int224).max, type(int32).max);
    }

    function testRoundTripFuzzSqrt(int224 signedCoefficient, int32 exponent) external {
        signedCoefficient = int224(bound(signedCoefficient, 1, type(int224).max));
        checkRoundTrip(signedCoefficient, exponent);
    }

    /// sqrt(n^2 10^(2k)) is n 10^k exactly for n below 1e20, whose root has
    /// fewer than the 41 digits pow keeps.
    function testSqrtExactSquares(uint256 n, int256 k) external pure {
        n = bound(n, 1, 1e20 - 1);
        k = bound(k, type(int32).min / 2, type(int32).max / 2);
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
            exponent = bound(exponent, type(int32).min, -100);
            shift = bound(shift, (type(int32).min - exponent) / 2, 0);
        } else {
            exponent = bound(exponent, 1, type(int32).max);
            shift = bound(shift, 0, (type(int32).max - exponent) / 2);
        }
        (int256 rootCoefficient, int256 rootExponent) =
            LibDecimalFloat.packLossless(signedCoefficient, exponent).sqrt().unpack();
        (int256 shiftedCoefficient, int256 shiftedExponent) =
            LibDecimalFloat.packLossless(signedCoefficient, exponent + 2 * shift).sqrt().unpack();
        assertTrue(
            LibExactFloat.eq(shiftedCoefficient, shiftedExponent, rootCoefficient, rootExponent + shift), "shift"
        );
    }

    /// floor(sqrt n) for n in [1e80, 1e82), by bisection on exact squares.
    function floorRoot(U512 memory n) internal pure returns (uint256) {
        uint256 low = 1e40;
        uint256 high = 1e41;
        while (high - low > 1) {
            uint256 mid = (low + high) / 2;
            if (LibExactFloat.cmp(LibExactFloat.mul(mid, mid), n) <= 0) {
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
    function referenceRoot(uint256 a, int256 exponent) internal pure returns (int256, int256) {
        while (a < 1e75) {
            a *= 10;
            exponent -= 1;
        }
        uint256 s = exponent % 2 == 0 ? 6 : 5;
        U512 memory n = LibExactFloat.mulPow10(LibExactFloat.u512(a), s);
        uint256 r = floorRoot(n);
        U512 memory midpointFloor = LibExactFloat.add(LibExactFloat.mul(r, r), LibExactFloat.u512(r));
        if (LibExactFloat.cmp(n, midpointFloor) > 0) {
            r += 1;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return (int256(r), (exponent - int256(s)) / 2);
    }

    function checkReference(int256 rootCoefficient, int256 rootExponent, uint256 a, int256 exponent) internal pure {
        (int256 expectedCoefficient, int256 expectedExponent) = referenceRoot(a, exponent);
        assertTrue(LibExactFloat.eq(rootCoefficient, rootExponent, expectedCoefficient, expectedExponent), "reference");
    }

    function testSqrtReferenceFuzz(int256 signedCoefficient, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, 1, type(int224).max);
        exponent = bound(exponent, type(int32).min, type(int32).max);
        (int256 rootCoefficient, int256 rootExponent) =
            LibDecimalFloat.packLossless(signedCoefficient, exponent).sqrt().unpack();
        // forge-lint: disable-next-line(unsafe-typecast)
        checkReference(rootCoefficient, rootExponent, uint256(signedCoefficient), exponent);
    }

    /// The implementation takes any coefficient below 1e76, as pow hands it.
    function testImplementationSqrtReferenceFuzz(uint256 coefficient, int256 exponent) external pure {
        coefficient = bound(coefficient, 1, 1e76 - 1);
        exponent = bound(exponent, type(int256).min + 81, type(int256).max);
        // coefficient is below 1e76, so it fits int256.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedCoefficient = int256(coefficient);
        (int256 rootCoefficient, int256 rootExponent) = LibDecimalFloatImplementation.sqrt(signedCoefficient, exponent);
        checkReference(rootCoefficient, rootExponent, coefficient, exponent);
    }

    function liveSqrt(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.sqrt(signedCoefficient, exponent);
    }

    /// The root before #359's seed, and the exact one.
    function checkPre359(uint256 coefficient, int256 exponent) internal pure {
        // coefficient is below 1e76, so it fits int256.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedCoefficient = int256(coefficient);
        (int256 rootCoefficient, int256 rootExponent) = LibDecimalFloatImplementation.sqrt(signedCoefficient, exponent);
        (int256 pre359Coefficient, int256 pre359Exponent) =
            LibDecimalFloatSqrtVariants.sqrtPre359(signedCoefficient, exponent);
        assertEq(rootCoefficient, pre359Coefficient, "pre-#359 coefficient");
        assertEq(rootExponent, pre359Exponent, "pre-#359 exponent");
        checkReference(rootCoefficient, rootExponent, coefficient, exponent);
    }

    function testImplementationSqrtPre359Fuzz(uint256 coefficient, int256 exponent) external pure {
        checkPre359(bound(coefficient, 1, 1e76 - 1), bound(exponent, type(int256).min + 81, type(int256).max));
    }

    function testImplementationSqrtPre359PackedFuzz(int224 signedCoefficient, int32 exponent) external pure {
        vm.assume(signedCoefficient > 0);
        // forge-lint: disable-next-line(unsafe-typecast)
        checkPre359(uint256(int256(signedCoefficient)), exponent);
    }

    /// 2^250 * 1e6 is 15625 * 2^256, so the low word of mulDiv's product is
    /// zero and the remainder borrows from the high word.
    function testImplementationSqrtPre359MulDivBorrow() external pure {
        checkPre359(2 ** 250, 0);
    }

    /// c * 1e6 is f^2 + f for f = 4e40, so its root is f + 0.5 - 1/(8f) and
    /// rounds to f. The seed lands on f exactly and the Newton quotient is
    /// f + 1, so (f + f + 1) >> 1 must round down: a quotient one too large
    /// gives f + 1, which the one-sided residual check cannot undo.
    function testImplementationSqrtPre359NewtonRoundsDown() external pure {
        checkPre359(16e74 + 4e34, 0);
    }

    /// c * 1e6 is 21248 * 2^256 + 2^256 - 64: the low word is within the
    /// high word of 2^256, so mul512's Chinese-remainder reconstruction of
    /// the high word must borrow.
    function testImplementationSqrtPre359Mul512Borrow() external pure {
        checkPre359(2460466104203731836555459860449609353974133904160196345274434202584146091719, 0);
    }

    /// The frozen scaleUp's gates, at each power of ten it compares against,
    /// for both exponent parities, and one below.
    function testImplementationSqrtPre359ScaleUpGates() external pure {
        uint256[7] memory gates = [uint256(1e38), 1e57, 1e66, 1e71, 1e73, 1e74, 1e75];
        for (uint256 i = 0; i < gates.length; i++) {
            checkPre359(gates[i], 0);
            checkPre359(gates[i], 1);
            checkPre359(gates[i] - 1, 0);
        }
    }

    /// At 26a3cf06 sqrt's `scaleUp` has no domain check, so 1e76, past its
    /// (0, 1e76) domain, returns a root where the live sqrt reverts
    /// `SqrtOutOfRange`.
    function testImplementationSqrtPre359CoefficientOutsideDomain() external {
        (int256 c, int256 e) = LibDecimalFloatSqrtVariants.sqrtPre359(1e76, 0);
        assertEq(c, 1e41);
        assertEq(e, -3);
        vm.expectRevert(abi.encodeWithSelector(SqrtOutOfRange.selector, int256(1e76), int256(0)));
        this.liveSqrt(1e76, 0);
    }

    /// At 26a3cf06 sqrt's unguarded `scaleUp` wraps 1 10^int256.min to 1e75
    /// 10^(int256.max - 74), so the root's exponent is int256.max / 2 - 39
    /// rather than the library's int256.min / 2 - 40 (#451). The baseline
    /// must reproduce that, not the live `scaleUp`'s `ScaleUpOutOfRange`.
    function testImplementationSqrtPre359ExponentFloorWraps() external pure {
        (int256 pre359Coefficient, int256 pre359Exponent) = LibDecimalFloatSqrtVariants.sqrtPre359(1, type(int256).min);
        assertEq(pre359Coefficient, 1e40, "pre-#359 coefficient");
        assertEq(pre359Exponent, type(int256).max / 2 - 39, "pre-#359 exponent");
        (int256 rootCoefficient, int256 rootExponent) = LibDecimalFloatImplementation.sqrt(1, type(int256).min);
        assertEq(rootCoefficient, 1e40, "coefficient");
        assertEq(rootExponent, type(int256).min / 2 - 40, "exponent");
    }

    /// The copied mulDiv's fast path, a product under 2^256, needs a
    /// coefficient outside (0, 1e76): inside, the scaled coefficient times 1e5
    /// is at least 1e80. Zero reaches it with quotient 0. c = 2 (5^38)^-1 mod
    /// 2^218, less 2^218 so `scaleUp` takes its first step, has c 1e38 = 2^39
    /// mod 2^256, and the six steps after scale that to 2^39 1e40, so the
    /// product is 2^39 1e46 and the quotient 16543612251060553497 is odd: the
    /// Newton step's `>> 1` sees it exactly. Expected values are what
    /// 26a3cf06's `sqrt` returns, run at that commit; the live sqrt reverts
    /// `SqrtOutOfRange` on both.
    function testImplementationSqrtPre359MulDivFastPath() external {
        int256 wrapped = -401255958304095716366485929147444023534941234139409265179255399566;
        (int256 c, int256 e) = LibDecimalFloatSqrtVariants.sqrtPre359(0, 0);
        assertEq(c, 166153499473114484112975882535043072000, "zero coefficient");
        assertEq(e, -42, "zero exponent");
        (c, e) = LibDecimalFloatSqrtVariants.sqrtPre359(wrapped, 0);
        assertEq(c, 166153499473114484124004789078756993248, "wrapped coefficient");
        assertEq(e, -42, "wrapped exponent");
        vm.expectRevert(abi.encodeWithSelector(SqrtOutOfRange.selector, int256(0), int256(0)));
        this.liveSqrt(0, 0);
        vm.expectRevert(abi.encodeWithSelector(SqrtOutOfRange.selector, wrapped, int256(0)));
        this.liveSqrt(wrapped, 0);
    }

    /// The seed is furthest from the root at the ends of E's decade and at
    /// E = a b: 312e73 for an even exponent, where E is the coefficient, and
    /// 3116e71 for an odd one, where it is the coefficient over 10.
    function testImplementationSqrtPre359SeedExtremes() external pure {
        uint256[3] memory even = [uint256(1e75), 312e73 - 10, 1e76 - 21];
        uint256[3] memory odd = [uint256(1e75), 3116e72 - 10, 1e76 - 21];
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 k = 0; k < 21; k++) {
                checkPre359(even[i] + k, 0);
                checkPre359(odd[i] + k, 1);
            }
        }
    }

    /// A 10^s is 2^256 - 2^(s + 5) mod 2^256 for A 10^s with s 5 and 6, so
    /// its 512 bit product's low word is within its high word of 2^256 and
    /// the high word takes a borrow.
    function testImplementationSqrtLowWordBorrow() external pure {
        uint256 odd = 3256073549353331415310816098444303968833951968797812660789547262302517205475;
        uint256 even = 2460466104203731836555459860449609353974133904160196345274434202584146091719;
        (uint256 oddHigh, uint256 oddLow) = Math.mul512(odd, 1e5);
        (uint256 evenHigh, uint256 evenLow) = Math.mul512(even, 1e6);
        assertEq(oddHigh, 2811, "odd high");
        assertEq(type(uint256).max - oddLow, 31, "odd low");
        assertEq(evenHigh, 21248, "even high");
        assertEq(type(uint256).max - evenLow, 63, "even low");
        // forge-lint: disable-next-line(unsafe-typecast)
        (int256 rootCoefficient, int256 rootExponent) = LibDecimalFloatImplementation.sqrt(int256(odd), -75);
        checkReference(rootCoefficient, rootExponent, odd, -75);
        // forge-lint: disable-next-line(unsafe-typecast)
        (rootCoefficient, rootExponent) = LibDecimalFloatImplementation.sqrt(int256(even), -76);
        checkReference(rootCoefficient, rootExponent, even, -76);
    }

    /// x < y implies sqrt(x) <= sqrt(y), down to adjacent coefficients.
    function testSqrtMonotone(int256 signedCoefficient, int256 gap, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, 1, type(int224).max - 1e3);
        gap = bound(gap, 1, 1e3);
        exponent = bound(exponent, type(int32).min, type(int32).max);
        Float low = LibDecimalFloat.packLossless(signedCoefficient, exponent).sqrt();
        Float high = LibDecimalFloat.packLossless(signedCoefficient + gap, exponent).sqrt();
        (int256 lowCoefficient, int256 lowExponent) = low.unpack();
        (int256 highCoefficient, int256 highExponent) = high.unpack();
        assertTrue(LibExactFloat.cmpParts(lowCoefficient, lowExponent, highCoefficient, highExponent) <= 0, "monotone");
    }

    function assertCorrectlyRounded(int256 signedCoefficient, int256 exponent, Float root) internal pure {
        (int256 rootCoefficient, int256 rootExponent) = root.unpack();
        assertSqrtCorrectlyRounded(signedCoefficient, exponent, rootCoefficient, rootExponent);
    }

    function testSqrtCorrectlyRoundedFuzz(int256 signedCoefficient, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, 1, type(int224).max);
        exponent = bound(exponent, type(int32).min, type(int32).max);
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
        k = bound(k, type(int32).min / 2, type(int32).max / 2);
        checkMidpoint(c, k);
    }
}
