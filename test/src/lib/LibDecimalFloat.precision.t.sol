// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LogTest} from "../../abstract/LogTest.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibTestTranscendental} from "test/lib/LibTestTranscendental.sol";
import {LibTestPrecision} from "test/lib/LibTestPrecision.sol";

/// log10, pow10, pow and sqrt against the fixed point references in
/// LibTestTranscendental and against each other, each within the bound
/// LibTestPrecision derives for it.
contract LibDecimalFloatPrecisionTest is LogTest {
    using LibDecimalFloat for Float;

    function log10External(Float a) external returns (Float) {
        return a.log10(logTables());
    }

    function pow10External(Float a) external returns (Float) {
        return a.pow10(logTables());
    }

    function powExternal(Float a, Float b) external returns (Float) {
        return a.pow(b, logTables());
    }

    function sqrtExternal(Float a) external returns (Float) {
        return a.sqrt(logTables());
    }

    function bound36(uint256 scaled) internal pure returns (Float) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return LibDecimalFloat.packLossless(int256(scaled), -36);
    }

    function assertWithin(Float error, uint256 scaled, string memory what) internal pure {
        assertTrue(error.lte(bound36(scaled)), what);
    }

    /// a with up to 1e9 added to its coefficient, held to int224.
    function stepUp(Float a, uint256 step) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = a.unpack();
        signedCoefficient += int256(bound(step, 0, 1e9));
        if (signedCoefficient > type(int224).max) {
            signedCoefficient = type(int224).max;
        }
        return LibDecimalFloat.packLossless(signedCoefficient, exponent);
    }

    /// Any positive float, with the exponent across int32 in three regions:
    /// near 1, near the top and near the bottom of the range.
    function positive(int224 coefficient, int32 exponent, uint8 region) internal pure returns (Float) {
        coefficient = int224(bound(coefficient, 1, type(int224).max));
        if (region % 3 == 0) {
            exponent = int32(bound(exponent, -140, 70));
        } else if (region % 3 == 1) {
            exponent = int32(bound(exponent, type(int32).max - 300, type(int32).max));
        } else {
            exponent = int32(bound(exponent, type(int32).min, type(int32).min + 300));
        }
        return LibDecimalFloat.packLossless(coefficient, exponent);
    }

    /// A float of magnitude below 10^digits, at most 2e9, with any exponent in
    /// [-90, 2], so 10^x packs.
    function exponentInput(int256 coefficient, int256 exponent, uint256 digits) internal pure returns (Float) {
        exponent = bound(exponent, -90, 2);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 magnitude = 10 ** bound(digits, 0, 9);
        if (magnitude > 2e9) {
            magnitude = 2e9;
        }
        uint256 limit;
        if (exponent >= 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            limit = magnitude / 10 ** uint256(exponent);
        } else {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 shift = uint256(-exponent);
            limit = shift > 58 ? uint256(int256(type(int224).max)) : magnitude * 10 ** shift;
            if (limit > uint256(int256(type(int224).max))) {
                limit = uint256(int256(type(int224).max));
            }
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        coefficient = bound(coefficient, -int256(limit), int256(limit));
        return LibDecimalFloat.packLossless(coefficient, exponent);
    }

    function log10Error(Float a) internal returns (Float) {
        return LibTestTranscendental.absoluteError(this.log10External(a), LibTestTranscendental.log10(a));
    }

    function pow10Error(Float x) internal returns (Float) {
        return LibTestTranscendental.relativeError(this.pow10External(x), LibTestTranscendental.pow10(x));
    }

    function powError(Float a, Float b) internal returns (Float) {
        return LibTestTranscendental.relativeError(this.powExternal(a, b), LibTestTranscendental.pow(a, b));
    }

    function sqrtError(Float a) internal returns (Float) {
        return LibTestTranscendental.relativeError(
            this.sqrtExternal(a), LibTestTranscendental.pow(a, LibDecimalFloat.FLOAT_HALF)
        );
    }

    /// |log10(a b) - log10 a - log10 b|.
    function log10ProductError(Float a, Float b) internal returns (Float) {
        return LibTestTranscendental.absoluteError(
            this.log10External(a.mul(b)), this.log10External(a).add(this.log10External(b))
        );
    }

    /// pow10(log10 a) / a - 1.
    function pow10Log10Error(Float a) internal returns (Float) {
        return LibTestTranscendental.relativeError(this.pow10External(this.log10External(a)), a);
    }

    /// pow(a, b) pow(a, c) / pow(a, b + c) - 1.
    function powProductError(Float a, Float b, Float c) internal returns (Float) {
        return LibTestTranscendental.relativeError(
            this.powExternal(a, b).mul(this.powExternal(a, c)), this.powExternal(a, b.add(c))
        );
    }

    /// sqrt(a)^2 / a - 1.
    function sqrtSquareError(Float a) internal returns (Float) {
        Float root = this.sqrtExternal(a);
        return LibTestTranscendental.relativeError(root, a.div(root));
    }

    /// A base with |log10 a| <= 210 and a power with |b| <= 1e6, or a base
    /// anywhere in range and |b| < 0.9, so |b log10 a| stays below 2.1e8 or
    /// 2e9 and a^b packs.
    function powInputs(int224 coefficientA, int32 exponentA, uint8 region, int256 coefficientB, int256 exponentB)
        internal
        pure
        returns (Float a, Float b)
    {
        a = positive(coefficientA, exponentA, region);
        exponentB = bound(exponentB, -76, 0);
        if (region % 3 == 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 shift = uint256(-exponentB);
            // shift <= 61 here, so 1e6 * 10^shift <= 1e67 fits int256.
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 limit = shift > 61 ? type(int224).max : int256(1e6 * 10 ** shift);
            coefficientB = bound(coefficientB, -limit, limit);
        } else {
            exponentB = bound(exponentB, -76, -1);
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 unit = exponentB < -67 ? type(int224).max : int256(9 * 10 ** uint256(-exponentB - 1));
            coefficientB = bound(coefficientB, -unit, unit);
        }
        b = LibDecimalFloat.packLossless(coefficientB, exponentB);
    }

    /// pow10 over every antilog table input, x = idx / 1e4 for idx 0-9999.
    /// Neighbours differ by 2.3e-4 relative, far above the 41 digit rounding,
    /// so the grid strictly increases.
    function testPow10Grid() external {
        Float previous = LibDecimalFloat.FLOAT_ZERO;
        for (uint256 idx = 0; idx < 10000; idx++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            Float x = LibDecimalFloat.packLossless(int256(idx), -4);
            Float actual = this.pow10External(x);
            assertTrue(actual.gt(previous), "pow10 grid increasing");
            previous = actual;
            assertWithin(
                LibTestTranscendental.relativeError(actual, LibTestTranscendental.pow10(x)),
                LibTestPrecision.POW10_MAX_ERROR,
                "pow10 grid"
            );
        }
    }

    /// log10 is non decreasing over every four digit mantissa.
    function testLog10GridMonotone() external {
        Float previous = this.log10External(LibDecimalFloat.packLossless(1000, 0));
        for (uint256 n = 1001; n < 10000; n++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            Float actual = this.log10External(LibDecimalFloat.packLossless(int256(n), 0));
            assertTrue(actual.gte(previous), "log10 grid monotone");
            previous = actual;
        }
    }

    function testLog10Reference(int224 coefficient, int32 exponent, uint8 region) external {
        assertWithin(log10Error(positive(coefficient, exponent, region)), LibTestPrecision.LOG10_MAX_ERROR, "log10");
    }

    /// log10(10^k) is exactly k, for every k a Float can hold, whatever power
    /// of ten carries it.
    function testLog10Anchors(int32 k, uint8 digits) external {
        int256 shift = int256(bound(digits, 0, 66));
        int256 exponent = bound(k, int256(type(int32).min), int256(type(int32).max) - shift);
        // forge-lint: disable-next-line(unsafe-typecast)
        Float a = LibDecimalFloat.packLossless(int256(10 ** uint256(shift)), exponent);
        assertTrue(this.log10External(a).eq(LibDecimalFloat.packLossless(exponent + shift, 0)), "log10 anchor");
    }

    function testLog10Monotone(int224 coefficient, int32 exponent, uint8 region, uint256 step) external {
        Float a = positive(coefficient, exponent, region);
        assertTrue(this.log10External(a).lte(this.log10External(stepUp(a, step))), "log10 monotone");
    }

    function testLog10MonotonePairs(
        int224 coefficientA,
        int32 exponentA,
        int224 coefficientB,
        int32 exponentB,
        uint8 region
    ) external {
        Float a = positive(coefficientA, exponentA, region);
        Float b = positive(coefficientB, exponentB, region);
        if (a.gt(b)) {
            (a, b) = (b, a);
        }
        assertTrue(this.log10External(a).lte(this.log10External(b)), "log10 monotone pairs");
    }

    function testLog10Product(int224 coefficientA, int32 exponentA, int224 coefficientB, int32 exponentB) external {
        Float a = positive(coefficientA, exponentA, 0);
        Float b = positive(coefficientB, exponentB, 0);
        assertWithin(log10ProductError(a, b), LibTestPrecision.LOG10_PRODUCT_MAX_ERROR, "log10 product");
    }

    function testPow10Reference(int256 coefficient, int256 exponent, uint256 digits) external {
        assertWithin(
            pow10Error(exponentInput(coefficient, exponent, digits)), LibTestPrecision.POW10_MAX_ERROR, "pow10"
        );
    }

    /// pow10(k) is exactly 10^k for every whole k whose power packs.
    function testPow10Anchors(int32 k) external {
        assertTrue(
            this.pow10External(LibDecimalFloat.packLossless(k, 0)).eq(LibDecimalFloat.packLossless(1, k)),
            "pow10 anchor"
        );
    }

    function testPow10Monotone(int256 coefficient, int256 exponent, uint256 digits, uint256 step) external {
        Float x = exponentInput(coefficient, exponent, digits);
        Float y = stepUp(x, step).min(LibDecimalFloat.packLossless(2e9, 0));
        assertTrue(this.pow10External(x).lte(this.pow10External(y)), "pow10 monotone");
    }

    function testPow10MonotonePairs(int256 coefficientX, int256 coefficientY, int256 exponent, uint256 digits)
        external
    {
        Float x = exponentInput(coefficientX, exponent, digits);
        Float y = exponentInput(coefficientY, exponent, digits);
        if (x.gt(y)) {
            (x, y) = (y, x);
        }
        assertTrue(this.pow10External(x).lte(this.pow10External(y)), "pow10 monotone pairs");
    }

    function testPow10Log10(int224 coefficient, int32 exponent) external {
        Float a = positive(coefficient, exponent, 0);
        assertWithin(pow10Log10Error(a), LibTestPrecision.POW10_LOG10_MAX_ERROR, "pow10 log10");
    }

    function testPowReference(int224 coefficientA, int32 exponentA, uint8 region, int256 coefficientB, int256 exponentB)
        external
    {
        (Float a, Float b) = powInputs(coefficientA, exponentA, region, coefficientB, exponentB);
        assertWithin(powError(a, b), LibTestPrecision.POW_MAX_ERROR, "pow");
    }

    function testPowProduct(
        int224 coefficientA,
        int32 exponentA,
        int256 coefficientB,
        int256 coefficientC,
        int256 exponentB
    ) external {
        (Float a, Float b) = powInputs(coefficientA, exponentA, 0, coefficientB, exponentB);
        (, Float c) = powInputs(coefficientA, exponentA, 0, coefficientC, exponentB);
        assertWithin(powProductError(a, b, c), LibTestPrecision.POW_PRODUCT_MAX_ERROR, "pow product");
    }

    /// For a fixed positive power, pow is non decreasing in the base.
    function testPowMonotoneInBase(
        int224 coefficientA,
        int32 exponentA,
        uint256 step,
        int256 coefficientB,
        int256 exponentB
    ) external {
        (Float a, Float b) = powInputs(coefficientA, exponentA, 0, coefficientB, exponentB);
        b = b.abs();
        assertTrue(this.powExternal(a, b).lte(this.powExternal(stepUp(a, step), b)), "pow monotone in base");
    }

    function testSqrtReference(int224 coefficient, int32 exponent, uint8 region) external {
        assertWithin(sqrtError(positive(coefficient, exponent, region)), LibTestPrecision.SQRT_MAX_ERROR, "sqrt");
    }

    function testSqrtSquare(int224 coefficient, int32 exponent, uint8 region) external {
        assertWithin(
            sqrtSquareError(positive(coefficient, exponent, region)),
            LibTestPrecision.SQRT_SQUARE_MAX_ERROR,
            "sqrt square"
        );
    }

    function testSqrtMonotone(int224 coefficient, int32 exponent, uint8 region, uint256 step) external {
        Float a = positive(coefficient, exponent, region);
        assertTrue(this.sqrtExternal(a).lte(this.sqrtExternal(stepUp(a, step))), "sqrt monotone");
    }
}
