// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LogTest} from "../../abstract/LogTest.sol";

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {PowNegativeBase} from "src/error/ErrDecimalFloat.sol";
import {console2} from "forge-std-1.17.0/src/Test.sol";
import {LibTestErrorBound} from "test/lib/LibTestErrorBound.sol";
import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";

contract LibDecimalFloatSqrtTest is LogTest {
    using LibDecimalFloat for Float;

    /// The root is within E of sqrt a and its square, rounded, within E2 of
    /// the root squared, so a over the square is within 2E + E2 of 1, plus
    /// higher orders and the quotient's packing, under 1e-65.
    function diffLimit() internal pure returns (Float) {
        Float error = LibTestErrorBound.sqrt();
        return error.add(error).add(LibTestErrorBound.pow(LibDecimalFloat.FLOAT_TWO))
            .add(LibDecimalFloat.packLossless(1, -65));
    }

    function sqrtExternal(Float a, address tables) external pure returns (Float) {
        return a.sqrt(tables);
    }

    function checkSqrt(
        int256 signedCoefficient,
        int256 exponent,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal {
        Float a = LibDecimalFloat.packLossless(signedCoefficient, exponent);
        address tables = logTables();
        uint256 beforeGas = gasleft();
        Float c = a.sqrt(tables);
        uint256 afterGas = gasleft();
        console2.log("Gas used:", beforeGas - afterGas);
        console2.logInt(signedCoefficient);
        console2.logInt(exponent);
        (int256 actualSignedCoefficient, int256 actualExponent) = c.unpack();
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signedCoefficient");
        assertEq(actualExponent, expectedExponent, "exponent");
    }

    function checkRoundTrip(int256 signedCoefficient, int256 exponent) internal {
        Float a = LibDecimalFloat.packLossless(signedCoefficient, exponent);
        address tables = logTables();
        Float c = a.sqrt(tables);
        Float roundTrip = c.pow(LibDecimalFloat.FLOAT_TWO, tables);

        Float diff = a.div(roundTrip).sub(LibDecimalFloat.FLOAT_ONE).abs();

        assertTrue(diff.lte(diffLimit()), "Round trip sqrt diff too high");
    }

    function testSqrt() external {
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
    ) internal {
        Float c = LibDecimalFloat.packLossless(signedCoefficient, exponent).sqrt(logTables());
        assertTrue(c.eq(LibDecimalFloat.packLossless(rootSignedCoefficient, rootExponent)), "exact");
    }

    function testSqrtExact() external {
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
        vm.assume(!a.isZero());

        if (a.gt(LibDecimalFloat.FLOAT_ZERO)) {
            a = a.minus();
        }

        address tables = logTables();

        (int256 signedCoefficient, int256 exponent) = a.unpack();
        vm.expectRevert(abi.encodeWithSelector(PowNegativeBase.selector, signedCoefficient, exponent));
        this.sqrtExternal(a, tables);
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
    }

    function testRoundTripFuzzSqrt(int224 signedCoefficient, int32 exponent) external {
        signedCoefficient = int224(bound(signedCoefficient, 1, type(int224).max));
        exponent = int32(bound(exponent, type(int16).min, type(int16).max));
        checkRoundTrip(signedCoefficient, exponent);
    }

    /// sqrt(n^2 10^(2k)) is n 10^k exactly for n below 1e20, whose root has
    /// fewer than the 41 digits pow keeps.
    function testSqrtExactSquares(uint256 n, int256 k) external {
        n = bound(n, 1, 1e20 - 1);
        k = bound(k, -1e9, 1e9);
        // forge-lint: disable-next-line(unsafe-typecast)
        Float root = LibDecimalFloat.packLossless(int256(n * n), 2 * k).sqrt(logTables());
        // forge-lint: disable-next-line(unsafe-typecast)
        assertTrue(root.eq(LibDecimalFloat.packLossless(int256(n), k)), "exact");
    }

    /// sqrt(x 100^k) is sqrt(x) 10^k exactly, as log10 sums the characteristic
    /// as an integer. x stays away from 1, where log10 keeps digits that a
    /// shift truncates.
    function testSqrtDecadeShift(int256 signedCoefficient, int256 exponent, int256 shift, bool small) external {
        signedCoefficient = bound(signedCoefficient, 1, type(int224).max);
        if (small) {
            exponent = bound(exponent, -1e9, -100);
            shift = bound(shift, -5e8, 0);
        } else {
            exponent = bound(exponent, 1, 1e9);
            shift = bound(shift, 0, 5e8);
        }
        address tables = logTables();
        Float root = LibDecimalFloat.packLossless(signedCoefficient, exponent).sqrt(tables);
        Float shifted = LibDecimalFloat.packLossless(signedCoefficient, exponent + 2 * shift).sqrt(tables);
        assertTrue(shifted.eq(root.mul(LibDecimalFloat.packLossless(1, shift))), "shift");
    }

    /// |sqrt(x) - true root| in billionths of a unit in the root's last
    /// place, from x / root^2 = 1 - 2 error to first order.
    function sqrtUlpError(int256 signedCoefficient, int256 exponent) internal returns (uint256) {
        signedCoefficient = bound(signedCoefficient, 1, type(int224).max);
        exponent = bound(exponent, -1e9, 1e9);
        (int256 rootCoefficient, int256 rootExponent) =
            LibDecimalFloat.packLossless(signedCoefficient, exponent).sqrt(logTables()).unpack();
        (int256 squareCoefficient, int256 squareExponent) =
            LibDecimalFloatImplementation.mul(rootCoefficient, rootExponent, rootCoefficient, rootExponent);
        (int256 ratioCoefficient, int256 ratioExponent) =
            LibDecimalFloatImplementation.div(signedCoefficient, exponent, squareCoefficient, squareExponent);
        (ratioCoefficient, ratioExponent) = LibDecimalFloatImplementation.sub(ratioCoefficient, ratioExponent, 1, 0);
        (ratioCoefficient, ratioExponent) =
            LibDecimalFloatImplementation.mul(ratioCoefficient, ratioExponent, rootCoefficient, 9);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 error = LibDecimalFloatImplementation.withTargetExponent(ratioCoefficient, ratioExponent, 0) / 2;
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(error < 0 ? -error : error);
    }

    /// Correctly rounded: within half a unit, and never at it as a root is
    /// never a midpoint. The estimate's second order and truncation are far
    /// below a billionth.
    function testSqrtUlpFuzz(int256 signedCoefficient, int256 exponent) external {
        assertLe(sqrtUlpError(signedCoefficient, exponent), 5e8, "sqrt error");
    }

    /// x < y implies sqrt(x) <= sqrt(y), down to adjacent coefficients.
    function testSqrtMonotone(int256 signedCoefficient, int256 gap, int256 exponent) external {
        signedCoefficient = bound(signedCoefficient, 1, type(int224).max - 1e3);
        gap = bound(gap, 1, 1e3);
        exponent = bound(exponent, -1e9, 1e9);
        address tables = logTables();
        Float low = LibDecimalFloat.packLossless(signedCoefficient, exponent).sqrt(tables);
        Float high = LibDecimalFloat.packLossless(signedCoefficient + gap, exponent).sqrt(tables);
        assertTrue(low.lte(high), "monotone");
    }

    /// x 10^d > m^2 in 512 bits, for x 10^d below 2^256 squared.
    function past(uint256 x, uint256 d, uint256 m) internal pure returns (bool) {
        (uint256 xHigh, uint256 xLow) = LibDecimalFloatImplementation.mul512(x, 10 ** d);
        (uint256 mHigh, uint256 mLow) = LibDecimalFloatImplementation.mul512(m, m);
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

    function testSqrtCorrectlyRoundedFuzz(int256 signedCoefficient, int256 exponent) external {
        signedCoefficient = bound(signedCoefficient, 1, type(int224).max);
        exponent = bound(exponent, -1e9, 1e9);
        Float root = LibDecimalFloat.packLossless(signedCoefficient, exponent).sqrt(logTables());
        assertCorrectlyRounded(signedCoefficient, exponent, root);
    }

    /// A = floor((c + 1/2)^2 / 1e16) has a root within 5e-25 of a unit below
    /// the midpoint (c + 1/2) 1e-8, and A + 1 a root above it, far inside
    /// pow's 3.6e-8 of a unit, so only the midpoint comparison rounds them:
    /// to c and to c + 1. 100^k scales the root by 10^k exactly.
    function checkMidpoint(uint256 c, int256 k) internal {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 a = int256(Math.mulDiv(2 * c + 1, 2 * c + 1, 4e16));
        address tables = logTables();
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedC = int256(c);
        assertTrue(
            LibDecimalFloat.packLossless(a, 2 * k).sqrt(tables).eq(LibDecimalFloat.packLossless(signedC, k - 8)),
            "below midpoint"
        );
        assertTrue(
            LibDecimalFloat.packLossless(a + 1, 2 * k).sqrt(tables)
                .eq(LibDecimalFloat.packLossless(signedC + 1, k - 8)),
            "above midpoint"
        );
        assertCorrectlyRounded(a, 2 * k, LibDecimalFloat.packLossless(a, 2 * k).sqrt(tables));
        assertCorrectlyRounded(a + 1, 2 * k, LibDecimalFloat.packLossless(a + 1, 2 * k).sqrt(tables));
    }

    /// The ends of the decade. At 1e41 - 1 the upper neighbour is 1e40 a
    /// decade up, so a root that pow rounds to 1e40 is checked against the
    /// midpoint 1e41 - 1/2 below it.
    function testSqrtMidpointEnds() external {
        checkMidpoint(1e40, 0);
        checkMidpoint(1e41 - 1, 0);
        checkMidpoint(1e41 - 1, -3);
        checkMidpoint(1e40, 5);
    }

    function testSqrtMidpointFuzz(uint256 c, int256 k) external {
        c = bound(c, 1e40, 1e41 - 1);
        k = bound(k, -5e8, 5e8);
        checkMidpoint(c, k);
    }
}
