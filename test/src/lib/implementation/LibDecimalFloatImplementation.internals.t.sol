// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LogTest} from "test/abstract/LogTest.sol";
import {MulDivOverflow} from "src/error/ErrDecimalFloat.sol";

/// @title Direct tests for internal functions that previously had no dedicated
/// test coverage (audit finding A09-11).
contract LibDecimalFloatImplementationInternalsTest is LogTest {
    // -- absUnsignedSignedCoefficient --

    function testAbsZero() external pure {
        assertEq(LibDecimalFloatImplementation.absUnsignedSignedCoefficient(0), 0);
    }

    function testAbsPositive(int256 x) external pure {
        x = bound(x, 1, type(int256).max);
        // Safe: x is bounded to [1, type(int256).max] so fits in uint256.
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(LibDecimalFloatImplementation.absUnsignedSignedCoefficient(x), uint256(x));
    }

    function testAbsNegative(int256 x) external pure {
        x = bound(x, type(int256).min + 1, -1);
        // Safe: x is negative so -x is positive and fits in uint256.
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(LibDecimalFloatImplementation.absUnsignedSignedCoefficient(x), uint256(-x));
    }

    function testAbsMinInt256() external pure {
        // type(int256).min has no positive counterpart in int256, but fits in uint256.
        assertEq(
            LibDecimalFloatImplementation.absUnsignedSignedCoefficient(type(int256).min), uint256(type(int256).max) + 1
        );
    }

    // -- mul512 --

    function testMul512Zero() external pure {
        (uint256 high, uint256 low) = LibDecimalFloatImplementation.mul512(0, 12345);
        assertEq(high, 0);
        assertEq(low, 0);
    }

    function testMul512NoOverflow(uint128 a, uint128 b) external pure {
        (uint256 high, uint256 low) = LibDecimalFloatImplementation.mul512(uint256(a), uint256(b));
        assertEq(high, 0);
        assertEq(low, uint256(a) * uint256(b));
    }

    function testMul512MaxValues() external pure {
        // type(uint256).max * type(uint256).max should produce a 512-bit result.
        (uint256 high, uint256 low) = LibDecimalFloatImplementation.mul512(type(uint256).max, type(uint256).max);
        // (2^256 - 1)^2 = 2^512 - 2^257 + 1
        // high = 2^256 - 2 = type(uint256).max - 1
        // low = 1
        assertEq(high, type(uint256).max - 1);
        assertEq(low, 1);
    }

    // -- mulDiv --

    function testMulDivSimple() external pure {
        // 6 * 7 / 3 = 14
        assertEq(LibDecimalFloatImplementation.mulDiv(6, 7, 3), 14);
    }

    function testMulDivLargeNumerator() external pure {
        // Test with values that overflow uint256 in intermediate multiplication.
        uint256 x = type(uint256).max;
        uint256 y = 2;
        uint256 d = 2;
        // (max * 2) / 2 = max
        assertEq(LibDecimalFloatImplementation.mulDiv(x, y, d), type(uint256).max);
    }

    function mulDivExternal(uint256 x, uint256 y, uint256 d) external pure returns (uint256) {
        return LibDecimalFloatImplementation.mulDiv(x, y, d);
    }

    function testMulDivOverflowReverts() external {
        // Result would be type(uint256).max^2 which exceeds uint256.
        vm.expectRevert(abi.encodeWithSelector(MulDivOverflow.selector, type(uint256).max, type(uint256).max, 1));
        this.mulDivExternal(type(uint256).max, type(uint256).max, 1);
    }

    // -- compareRescale --

    function testCompareRescaleSameExponent() external pure {
        (int256 a, int256 b) = LibDecimalFloatImplementation.compareRescale(5, 0, 3, 0);
        assertEq(a, 5);
        assertEq(b, 3);
    }

    function testCompareRescaleDifferentExponents() external pure {
        // 5e2 vs 3e3 => rescale to compare: 5 vs 30
        (int256 a, int256 b) = LibDecimalFloatImplementation.compareRescale(5, 2, 3, 3);
        // After rescaling, a < b should hold (500 < 3000)
        assertTrue(a < b);
    }

    function testCompareRescaleEqual() external pure {
        // 50e1 vs 5e2 are equal (both 500)
        (int256 a, int256 b) = LibDecimalFloatImplementation.compareRescale(50, 1, 5, 2);
        assertEq(a, b);
    }

    // -- mantissa4 --

    function testMantissa4Zero() external pure {
        (int256 idx, bool interpolate, int256 scale) = LibDecimalFloatImplementation.mantissa4(0, -1);
        assertEq(idx, 0);
        assertFalse(interpolate);
        assertEq(scale, 1);
    }

    function testMantissa4ExactLookup() external pure {
        // 5000e-4 = 0.5, mantissa should be exact at index 5000
        (int256 idx, bool interpolate, int256 scale) = LibDecimalFloatImplementation.mantissa4(5000, -4);
        assertEq(idx, 5000);
        assertFalse(interpolate);
        assertEq(scale, 1);
    }

    /// Exponent exactly -4: the coefficient is already the first 4 mantissa
    /// digits, so it is returned verbatim with no interpolation and unit scale,
    /// for any coefficient.
    function testMantissa4FuzzExponentMinus4(int256 signedCoefficient) external pure {
        (int256 idx, bool interpolate, int256 scale) = LibDecimalFloatImplementation.mantissa4(signedCoefficient, -4);
        assertEq(idx, signedCoefficient);
        assertFalse(interpolate);
        assertEq(scale, 1);
    }

    /// Exponent in [-3, -1]: the coefficient is scaled UP to 4 digits by
    /// multiplying by 10^(4 + exponent). Never interpolates, unit scale.
    /// The coefficient is bounded so the scaled value stays in int256 range,
    /// matching the realistic fractional-part domain (its magnitude is always
    /// strictly less than 10^(-exponent)).
    function testMantissa4FuzzExponentMinus3ToMinus1(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, -3, -1);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 factor = int256(10 ** uint256(4 + exponent));
        // Keep signedCoefficient * factor within int256 to avoid overflow that
        // the production code tolerates via `unchecked`.
        signedCoefficient = bound(signedCoefficient, type(int256).min / factor, type(int256).max / factor);

        (int256 idx, bool interpolate, int256 scale) =
            LibDecimalFloatImplementation.mantissa4(signedCoefficient, exponent);
        assertEq(idx, signedCoefficient * factor);
        assertFalse(interpolate);
        assertEq(scale, 1);
    }

    /// Exponent >= 0: there is no fractional mantissa to look up, so the index
    /// is always 0 with no interpolation and unit scale, for any coefficient.
    function testMantissa4FuzzExponentNonNegative(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, 0, type(int256).max);
        (int256 idx, bool interpolate, int256 scale) =
            LibDecimalFloatImplementation.mantissa4(signedCoefficient, exponent);
        assertEq(idx, 0);
        assertFalse(interpolate);
        assertEq(scale, 1);
    }

    /// Exponent in [-80, -5]: the coefficient is scaled DOWN to its first 4
    /// digits by truncating division against scale = 10^(-(exponent + 4)).
    /// Interpolation is required exactly when that division was lossy, i.e.
    /// rescaled * scale != signedCoefficient.
    function testMantissa4FuzzExponentMinus80ToMinus5(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, -80, -5);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 scale = int256(10 ** uint256(-(exponent + 4)));
        int256 expectedRescaled = signedCoefficient / scale;
        bool expectedInterpolate = expectedRescaled * scale != signedCoefficient;

        (int256 idx, bool interpolate, int256 resultScale) =
            LibDecimalFloatImplementation.mantissa4(signedCoefficient, exponent);
        assertEq(idx, expectedRescaled);
        assertEq(interpolate, expectedInterpolate);
        assertEq(resultScale, scale);
    }

    /// Exponent < -80: the value is below the resolution of the 4-digit
    /// mantissa, so the index collapses to 0 with unit scale. Interpolation is
    /// flagged for any non-zero coefficient (there is some lost magnitude) and
    /// not for zero.
    function testMantissa4FuzzExponentBelowMinus80(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, type(int256).min, -81);
        (int256 idx, bool interpolate, int256 scale) =
            LibDecimalFloatImplementation.mantissa4(signedCoefficient, exponent);
        assertEq(idx, 0);
        assertEq(interpolate, signedCoefficient != 0);
        assertEq(scale, 1);
    }

    // -- unitLinearInterpolation --

    function testUnitLinearInterpolationExact() external pure {
        // When x1 == x, should return (y1, yExponent)
        (int256 resultCoeff, int256 resultExp) =
            LibDecimalFloatImplementation.unitLinearInterpolation(100, 100, 200, -2, 500, 600, -3);
        assertEq(resultCoeff, 500);
        assertEq(resultExp, -3);
    }

    function testUnitLinearInterpolationMidpoint() external pure {
        // x1=0, x=5000, x2=10000, y1=1000, y2=2000, all at exponent -4
        // Midpoint interpolation: y = 1000 + (5000/10000) * (2000 - 1000) = 1500e-4
        (int256 resultCoeff, int256 resultExp) =
            LibDecimalFloatImplementation.unitLinearInterpolation(0, 5000, 10000, -4, 1000, 2000, -4);
        assertTrue(LibDecimalFloatImplementation.eq(resultCoeff, resultExp, 1500, -4));
    }
}
