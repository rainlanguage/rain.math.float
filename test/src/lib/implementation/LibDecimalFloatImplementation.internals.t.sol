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

    // -- mantissa4 adversarial boundary tests --
    //
    // These tests do NOT mirror the production arithmetic. Each one pins a
    // concrete, hand-derived (idx, interpolate, scale) triple, or asserts an
    // independent safety invariant, so that an internal mutation that the
    // production-faithful fuzz tests would silently track is still caught.

    // int224 / int32 boundary constants (the real domain of a packed Float).
    int256 internal constant INT224_MAX = (int256(1) << 223) - 1;
    int256 internal constant INT224_MIN = -(int256(1) << 223);

    /// Exponent exactly -4 is its own branch (`exponent == -4`), distinct from
    /// the neighbouring branches. Pin the exact int224 boundary coefficients so a
    /// mutant that widens/narrows the `== -4` check (e.g. to `<= -4` swallowing
    /// the scale branch, or `>= -4` swallowing the [-3,-1] branch) is caught: at
    /// -4 the coefficient passes through verbatim, scale 1, never interpolates.
    function testMantissa4ExponentMinus4BoundaryCoefficients() external pure {
        int256[4] memory coeffs = [INT224_MAX, INT224_MIN, int256(1), int256(-1)];
        for (uint256 i = 0; i < coeffs.length; i++) {
            (int256 idx, bool interpolate, int256 scale) = LibDecimalFloatImplementation.mantissa4(coeffs[i], -4);
            assertEq(idx, coeffs[i]);
            assertFalse(interpolate);
            assertEq(scale, 1);
        }
    }

    /// The `exponent < -80` vs `>= -80` split is load-bearing: at -80 the scale
    /// is 10^76 (the largest power of ten that still fits in int256), at -81 it
    /// would be 10^77 which overflows int256 to a NEGATIVE number and corrupts
    /// the division. Pin both sides with concrete values so a mutant moving the
    /// bound (`< -80` -> `< -81`, `<= -80`, etc.) is killed deterministically
    /// rather than only probabilistically by the fuzzers.
    function testMantissa4ExponentMinus80IsScaleBranch() external pure {
        // -80 is INSIDE the scale branch: scale = 10^76. Note 10^76 is the
        // largest power of ten below int256.max, so the only single-digit
        // exact multiples that still fit are 1..5 (6 * 10^76 > int256.max).
        int256 scale76 = int256(10 ** 76);
        // A coefficient that divides exactly: 5 * 10^76 -> idx 5, no interpolation.
        (int256 idx, bool interpolate, int256 scale) = LibDecimalFloatImplementation.mantissa4(5 * scale76, -80);
        assertEq(idx, 5);
        assertFalse(interpolate);
        assertEq(scale, scale76);

        // One above an exact multiple -> truncates -> interpolate.
        (idx, interpolate, scale) = LibDecimalFloatImplementation.mantissa4(5 * scale76 + 1, -80);
        assertEq(idx, 5);
        assertTrue(interpolate);
        assertEq(scale, scale76);
    }

    /// -81 is INSIDE the below-resolution branch: idx collapses to 0, scale 1,
    /// interpolate iff coefficient != 0. If the `< -80` bound were widened to
    /// include -81 in the scale branch, scale would be 10^77 (negative int256)
    /// and idx would be a nonzero garbage value, failing these assertions.
    function testMantissa4ExponentMinus81IsBelowResolution() external pure {
        (int256 idx, bool interpolate, int256 scale) = LibDecimalFloatImplementation.mantissa4(INT224_MAX, -81);
        assertEq(idx, 0);
        assertTrue(interpolate);
        assertEq(scale, 1);

        (idx, interpolate, scale) = LibDecimalFloatImplementation.mantissa4(0, -81);
        assertEq(idx, 0);
        assertFalse(interpolate);
        assertEq(scale, 1);
    }

    /// The truncation-vs-interpolate flag at the exact edge of the scale branch.
    /// exponent -5 -> scale 10. A coefficient that is an exact multiple of 10
    /// must NOT interpolate; one digit above it MUST interpolate. This pins the
    /// `rescaled * scale != signedCoefficient` predicate independently of how
    /// production computes it (a flipped comparison or a wrong rounding mode
    /// breaks exactly one of the two assertions).
    function testMantissa4TruncationFlagEdgeMinus5() external pure {
        // 50000e-5 = 0.5 exactly -> idx 5000, no interpolation.
        (int256 idx, bool interpolate, int256 scale) = LibDecimalFloatImplementation.mantissa4(50000, -5);
        assertEq(idx, 5000);
        assertFalse(interpolate);
        assertEq(scale, 10);

        // 50001e-5 has a fifth significant digit -> truncates -> interpolate.
        (idx, interpolate, scale) = LibDecimalFloatImplementation.mantissa4(50001, -5);
        assertEq(idx, 5000);
        assertTrue(interpolate);
        assertEq(scale, 10);
    }

    /// Negative coefficients in the scale branch must truncate toward zero (as
    /// Solidity integer division does) and flag interpolation on any remainder.
    /// -50001e-5 -> idx -5000 (truncated toward zero), interpolate true.
    function testMantissa4NegativeTruncationMinus5() external pure {
        (int256 idx, bool interpolate, int256 scale) = LibDecimalFloatImplementation.mantissa4(-50001, -5);
        assertEq(idx, -5000);
        assertTrue(interpolate);
        assertEq(scale, 10);

        (idx, interpolate, scale) = LibDecimalFloatImplementation.mantissa4(-50000, -5);
        assertEq(idx, -5000);
        assertFalse(interpolate);
        assertEq(scale, 10);
    }

    /// int256.min in the scale branch: division never overflows (scale is always
    /// positive so `int256.min / scale` is safe), `rescaled * scale` cannot
    /// overflow because its magnitude is <= |int256.min|, and the lost low digit
    /// forces interpolate = true. Independent oracle: int256.min is not a
    /// multiple of 10, so truncation is always lossy here.
    function testMantissa4Int256MinScaleBranch() external pure {
        int256 scale10 = 10;
        (int256 idx, bool interpolate, int256 scale) = LibDecimalFloatImplementation.mantissa4(type(int256).min, -5);
        assertEq(idx, type(int256).min / scale10);
        assertTrue(interpolate);
        assertEq(scale, scale10);
        // Safety: idx really is the truncated quotient and reconstructing loses
        // the low digit (proving the interpolate flag is justified).
        assertTrue(idx * scale10 != type(int256).min);
    }

    /// The [-3,-1] branch scales UP exactly (factor is a power of ten), so it
    /// must never interpolate and the result must be exactly divisible back by
    /// the factor. Pin the two endpoints -1 and -3, and the -4/-5 neighbours to
    /// guard the branch's lower edge.
    function testMantissa4ScaleUpBranchExact() external pure {
        // exponent -1 -> factor 10^3 = 1000. 7e-1 = 0.7 -> mantissa 7000.
        (int256 idx, bool interpolate, int256 scale) = LibDecimalFloatImplementation.mantissa4(7, -1);
        assertEq(idx, 7000);
        assertFalse(interpolate);
        assertEq(scale, 1);

        // exponent -3 -> factor 10^1 = 10. 123e-3 = 0.123 -> mantissa 1230.
        (idx, interpolate, scale) = LibDecimalFloatImplementation.mantissa4(123, -3);
        assertEq(idx, 1230);
        assertFalse(interpolate);
        assertEq(scale, 1);
    }

    /// The `exponent >= 0` branch: zero index, no interpolation, unit scale, even
    /// at the int32 / int256 exponent extremes and the int224 coefficient bounds.
    /// A mutant turning `>= 0` into `> 0` would push exponent 0 into the [-3,-1]
    /// else-branch, where it would multiply by 10^4 and (for a nonzero
    /// coefficient) return a nonzero idx, failing the exponent-0 assertion.
    function testMantissa4NonNegativeBoundaries() external pure {
        int256[3] memory exps = [int256(0), int256(type(int32).max), type(int256).max];
        for (uint256 i = 0; i < exps.length; i++) {
            (int256 idx, bool interpolate, int256 scale) = LibDecimalFloatImplementation.mantissa4(INT224_MAX, exps[i]);
            assertEq(idx, 0);
            assertFalse(interpolate);
            assertEq(scale, 1);
        }
    }

    /// Independent safety invariant across the entire negative-exponent domain:
    /// whenever the function reports `interpolate == false`, the reported idx
    /// MUST losslessly reconstruct the input at the reported scale
    /// (idx * scale == signedCoefficient for the scale branch, idx == sc * factor
    /// implies exact for the others). Conversely, the value the mantissa stands
    /// for must be recoverable. This is the property the pow10 caller relies on:
    /// a false interpolate flag is a promise of exactness. Fuzzed across the
    /// realistic int224 coefficient / int32-style exponent domain.
    function testMantissa4InterpolateFalseImpliesExact(int256 signedCoefficient, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, INT224_MIN, INT224_MAX);
        exponent = bound(exponent, -80, -5);
        (int256 idx, bool interpolate, int256 scale) =
            LibDecimalFloatImplementation.mantissa4(signedCoefficient, exponent);
        if (!interpolate) {
            // No interpolation promised => the division was exact.
            assertEq(idx * scale, signedCoefficient);
        } else {
            // Interpolation flagged => there really was a remainder.
            assertTrue(idx * scale != signedCoefficient);
        }
        // The reported scale is always the exact power of ten for the exponent.
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(scale, int256(10 ** uint256(-(exponent + 4))));
    }

    /// Safety invariant for the below-resolution branch over the realistic
    /// int224 domain and full int32-style negative exponent range below -80:
    /// idx is always 0, scale always 1, and the interpolate flag is true exactly
    /// when information (a nonzero coefficient) was discarded. This is what makes
    /// the flag a faithful "we lost magnitude" signal.
    function testMantissa4BelowResolutionFlagIsFaithful(int256 signedCoefficient, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, INT224_MIN, INT224_MAX);
        exponent = bound(exponent, type(int32).min, -81);
        (int256 idx, bool interpolate, int256 scale) =
            LibDecimalFloatImplementation.mantissa4(signedCoefficient, exponent);
        assertEq(idx, 0);
        assertEq(scale, 1);
        assertEq(interpolate, signedCoefficient != 0);
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
