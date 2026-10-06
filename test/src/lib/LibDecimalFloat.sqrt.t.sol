// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LogTest} from "../../abstract/LogTest.sol";

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {PowNegativeBase} from "src/error/ErrDecimalFloat.sol";
import {console2} from "forge-std-1.17.0/src/Test.sol";
import {LibTestErrorBound} from "test/lib/LibTestErrorBound.sol";

contract LibDecimalFloatSqrtTest is LogTest {
    using LibDecimalFloat for Float;

    /// The root is within E of sqrt a and its square, rounded, within E2 of
    /// the root squared, so a over the square is within 2E + E2 of 1, plus
    /// higher orders and the quotient's packing, under 1e-65.
    function diffLimit() internal pure returns (Float) {
        Float error = LibTestErrorBound.pow(LibDecimalFloat.FLOAT_HALF);
        return error.add(error).add(LibTestErrorBound.pow(LibDecimalFloat.FLOAT_TWO))
            .add(LibDecimalFloat.packLossless(1, -65));
    }

    function sqrtExternal(Float a, address tables) external view returns (Float) {
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
        (int256 signedCoefficient, int256 exponent) = a.unpack();
        vm.assume(signedCoefficient != 0);
        if (signedCoefficient > 0) {
            // A positive int224 coefficient negates exactly.
            signedCoefficient = -signedCoefficient;
            a = LibDecimalFloat.packLossless(signedCoefficient, exponent);
        }

        address tables = logTables();

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

    /// pow10 rounds to nearest with its fixed point power within
    /// `POW10_RAW_ERROR` units, 5166.2 billionths of a unit, and its argument
    /// is half log10Unrounded, within half of 2.245e-47, which moves the root
    /// by 2.5847e-47 relative, 2584.7 billionths of a unit at most 1e-41
    /// relative. With the half unit that is under 500007751.
    function testSqrtUlpFuzz(int256 signedCoefficient, int256 exponent) external {
        assertLe(sqrtUlpError(signedCoefficient, exponent), 500007751, "sqrt error");
    }

    /// x < y implies sqrt(x) <= sqrt(y) + 2E, down to adjacent coefficients.
    function testSqrtMonotone(int256 signedCoefficient, int256 gap, int256 exponent) external {
        signedCoefficient = bound(signedCoefficient, 1, type(int224).max - 1e3);
        gap = bound(gap, 1, 1e3);
        exponent = bound(exponent, -1e9, 1e9);
        address tables = logTables();
        Float low = LibDecimalFloat.packLossless(signedCoefficient, exponent).sqrt(tables);
        Float high = LibDecimalFloat.packLossless(signedCoefficient + gap, exponent).sqrt(tables);
        Float error = LibTestErrorBound.pow(LibDecimalFloat.FLOAT_HALF);
        assertTrue(LibTestErrorBound.monotoneRelative(low, high, error, error), "monotone");
    }
}
