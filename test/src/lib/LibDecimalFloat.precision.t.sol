// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LogTest} from "../../abstract/LogTest.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibTranscendentalOracle} from "test/lib/LibTranscendentalOracle.sol";
import {LibTestErrorBound} from "test/lib/LibTestErrorBound.sol";

/// log10, pow10, pow and sqrt against the `bc` constant oracle, within 1e-67,
/// and against each other, each within the proven bound LibTestErrorBound
/// gives it.
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

    function assertWithin(int256 errorCoefficient, int256 errorExponent, Float bound, string memory what)
        internal
        pure
    {
        (int256 boundCoefficient, int256 boundExponent) = bound.unpack();
        if (errorCoefficient < 0) {
            errorCoefficient = -errorCoefficient;
        }
        assertTrue(
            LibDecimalFloatImplementation.lte(errorCoefficient, errorExponent, boundCoefficient, boundExponent), what
        );
    }

    function assertWithin(Float error, Float bound, string memory what) internal pure {
        assertTrue(error.lte(bound), what);
    }

    function relativeError(Float actual, Float expected) internal pure returns (Float) {
        return actual.div(expected).sub(LibDecimalFloat.FLOAT_ONE).abs();
    }

    function absoluteError(Float actual, Float expected) internal pure returns (Float) {
        return actual.sub(expected).abs();
    }

    /// actual / (power 10^exponent) - 1, unpacked.
    function relativeError(Float actual, uint256 power, int256 exponent) internal pure returns (int256, int256) {
        (int256 signedCoefficient, int256 actualExponent) = actual.unpack();
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedPower = int256(power);
        (signedCoefficient, actualExponent) =
            LibDecimalFloatImplementation.div(signedCoefficient, actualExponent, signedPower, exponent);
        return LibDecimalFloatImplementation.sub(signedCoefficient, actualExponent, 1, 0);
    }

    /// The oracle's 1e-67 relative, through the quotient and its truncation.
    function exp10Slack() internal pure returns (Float) {
        return LibDecimalFloat.packLossless(1, -66);
    }

    /// The oracle's a^b relative error: y = b log10 a is within |b| 1e-67
    /// plus 2 |y| 1e-75 from the 76 digit add and mul, at most 4.2e-66 for
    /// |y| up to 2.1e9, so 10^y within ln 10 of that, plus the 1e-67 of the
    /// oracle's power and the quotient.
    function powSlack(Float b) internal pure returns (Float) {
        return b.abs().mul(LibDecimalFloat.packLossless(3, -67)).add(LibDecimalFloat.packLossless(2, -65));
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

    /// log10 a from the oracle as characteristic + fraction / 1e70, unpacked.
    function oracleLog10(Float a) internal pure returns (int256, int256) {
        (int256 signedCoefficient, int256 exponent) = a.unpack();
        // a is positive.
        // forge-lint: disable-next-line(unsafe-typecast)
        (int256 characteristic, uint256 fraction) = LibTranscendentalOracle.log10(uint256(signedCoefficient), exponent);
        // forge-lint: disable-next-line(unsafe-typecast)
        return LibDecimalFloatImplementation.add(characteristic, 0, int256(fraction), -70);
    }

    /// log10 a within half a unit plus `LOG10_RAW_ERROR` units of 1e-50, plus
    /// the oracle's 1e-67.
    function assertLog10Reference(Float a, string memory what) internal {
        Float actual = this.log10External(a);
        (int256 actualCoefficient, int256 actualExponent) = actual.unpack();
        (int256 expectedCoefficient, int256 expectedExponent) = oracleLog10(a);
        (int256 errorCoefficient, int256 errorExponent) =
            LibDecimalFloatImplementation.sub(actualCoefficient, actualExponent, expectedCoefficient, expectedExponent);
        assertWithin(
            errorCoefficient,
            errorExponent,
            LibTestErrorBound.log10(actual).add(LibDecimalFloat.packLossless(1, -67)),
            what
        );
    }

    function assertPow10Reference(Float x, Float actual, string memory what) internal pure {
        (int256 signedCoefficient, int256 exponent) = x.unpack();
        (uint256 power, int256 powerExponent) = LibTranscendentalOracle.exp10(signedCoefficient, exponent);
        (int256 errorCoefficient, int256 errorExponent) = relativeError(actual, power, powerExponent);
        assertWithin(errorCoefficient, errorExponent, LibTestErrorBound.pow10().add(exp10Slack()), what);
    }

    /// 10^(b log10 a) from the oracle.
    function oraclePow(Float a, Float b) internal pure returns (uint256, int256) {
        (int256 logCoefficient, int256 logExponent) = oracleLog10(a);
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.mul(signedCoefficientB, exponentB, logCoefficient, logExponent);
        return LibTranscendentalOracle.exp10(signedCoefficient, exponent);
    }

    /// a^b within LibTestErrorBound.pow(b) of 10^(b log10 a) from the oracle.
    function assertPowReference(Float a, Float b, Float actual, string memory what) internal pure {
        (uint256 power, int256 powerExponent) = oraclePow(a, b);
        (int256 errorCoefficient, int256 errorExponent) = relativeError(actual, power, powerExponent);
        assertWithin(errorCoefficient, errorExponent, LibTestErrorBound.pow(b).add(powSlack(b)), what);
    }

    /// The product's packing moves its log by under 4.4e-67, and each packed
    /// sum or difference of logs at most 420 loses under 4.2e-64.
    function log10ProductSlack() internal pure returns (Float) {
        return LibDecimalFloat.packLossless(1, -63);
    }

    /// Each packed quotient, product or difference near 1 loses under 1e-66.
    function packingSlack() internal pure returns (Float) {
        return LibDecimalFloat.packLossless(1, -65);
    }

    /// |log10(a b) - log10 a - log10 b| within the three logs' bounds.
    function assertLog10Product(Float a, Float b) internal {
        Float logA = this.log10External(a);
        Float logB = this.log10External(b);
        Float logProduct = this.log10External(a.mul(b));
        assertWithin(
            absoluteError(logProduct, logA.add(logB)),
            LibTestErrorBound.log10(logProduct).add(LibTestErrorBound.log10(logA)).add(LibTestErrorBound.log10(logB))
                .add(log10ProductSlack()),
            "log10 product"
        );
    }

    /// pow10(log10 a) / a - 1. The log is within E of log10 a, which moves
    /// the power by under 2.3027 E relative for E below 1e-30.
    function assertPow10Log10(Float a) internal {
        Float log = this.log10External(a);
        assertWithin(
            relativeError(this.pow10External(log), a),
            LibTestErrorBound.pow10().add(LibTestErrorBound.log10(log).mul(LibDecimalFloat.packLossless(23027, -4)))
                .add(packingSlack()),
            "pow10 log10"
        );
    }

    /// pow(a, b) pow(a, c) / pow(a, b + c) - 1, within the three powers'
    /// bounds. Packing b + c moves the exponent by under 1e-66 of it, at most
    /// 2e6 times log10 a at most 210, so the power by under 1e-57.
    function assertPowProduct(Float a, Float b, Float c) internal {
        Float sum = b.add(c);
        assertWithin(
            relativeError(this.powExternal(a, b).mul(this.powExternal(a, c)), this.powExternal(a, sum)),
            LibTestErrorBound.pow(b).add(LibTestErrorBound.pow(c)).add(LibTestErrorBound.pow(sum))
                .add(LibDecimalFloat.packLossless(2, -57)),
            "pow product"
        );
    }

    /// sqrt(a)^2 / a - 1, within twice the root's bound plus its square.
    function assertSqrtSquare(Float a) internal {
        Float root = this.sqrtExternal(a);
        Float error = LibTestErrorBound.pow(LibDecimalFloat.FLOAT_HALF);
        assertWithin(
            relativeError(root, a.div(root)), error.add(error).add(error.mul(error)).add(packingSlack()), "sqrt square"
        );
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
            assertPow10Reference(x, actual, "pow10 grid");
        }
    }

    /// log10 is non decreasing over every four digit mantissa. Neighbours'
    /// logs differ by over 4.3e-5, far above twice its error bound.
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
        assertLog10Reference(positive(coefficient, exponent, region), "log10");
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

    function assertLog10Monotone(Float a, Float b, string memory what) internal {
        Float low = this.log10External(a);
        Float high = this.log10External(b);
        assertTrue(
            LibTestErrorBound.monotoneAbsolute(low, high, LibTestErrorBound.log10(low), LibTestErrorBound.log10(high)),
            what
        );
    }

    function testLog10Monotone(int224 coefficient, int32 exponent, uint8 region, uint256 step) external {
        Float a = positive(coefficient, exponent, region);
        assertLog10Monotone(a, stepUp(a, step), "log10 monotone");
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
        assertLog10Monotone(a, b, "log10 monotone pairs");
    }

    function testLog10Product(int224 coefficientA, int32 exponentA, int224 coefficientB, int32 exponentB) external {
        Float a = positive(coefficientA, exponentA, 0);
        Float b = positive(coefficientB, exponentB, 0);
        assertLog10Product(a, b);
    }

    function testPow10Reference(int256 coefficient, int256 exponent, uint256 digits) external {
        Float x = exponentInput(coefficient, exponent, digits);
        assertPow10Reference(x, this.pow10External(x), "pow10");
    }

    /// pow10(k) is exactly 10^k for every whole k whose power packs.
    function testPow10Anchors(int32 k) external {
        assertTrue(
            this.pow10External(LibDecimalFloat.packLossless(k, 0)).eq(LibDecimalFloat.packLossless(1, k)),
            "pow10 anchor"
        );
    }

    function assertPow10Monotone(Float x, Float y, string memory what) internal {
        assertTrue(
            LibTestErrorBound.monotoneRelative(
                this.pow10External(x), this.pow10External(y), LibTestErrorBound.pow10(), LibTestErrorBound.pow10()
            ),
            what
        );
    }

    function testPow10Monotone(int256 coefficient, int256 exponent, uint256 digits, uint256 step) external {
        Float x = exponentInput(coefficient, exponent, digits);
        Float y = stepUp(x, step).min(LibDecimalFloat.packLossless(2e9, 0));
        assertPow10Monotone(x, y, "pow10 monotone");
    }

    function testPow10MonotonePairs(int256 coefficientX, int256 coefficientY, int256 exponent, uint256 digits)
        external
    {
        Float x = exponentInput(coefficientX, exponent, digits);
        Float y = exponentInput(coefficientY, exponent, digits);
        if (x.gt(y)) {
            (x, y) = (y, x);
        }
        assertPow10Monotone(x, y, "pow10 monotone pairs");
    }

    function testPow10Log10(int224 coefficient, int32 exponent) external {
        Float a = positive(coefficient, exponent, 0);
        assertPow10Log10(a);
    }

    function testPowReference(int224 coefficientA, int32 exponentA, uint8 region, int256 coefficientB, int256 exponentB)
        external
    {
        (Float a, Float b) = powInputs(coefficientA, exponentA, region, coefficientB, exponentB);
        assertPowReference(a, b, this.powExternal(a, b), "pow");
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
        assertPowProduct(a, b, c);
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
        Float error = LibTestErrorBound.pow(b);
        assertTrue(
            LibTestErrorBound.monotoneRelative(
                this.powExternal(a, b), this.powExternal(stepUp(a, step), b), error, error
            ),
            "pow monotone in base"
        );
    }

    function testSqrtReference(int224 coefficient, int32 exponent, uint8 region) external {
        Float a = positive(coefficient, exponent, region);
        assertPowReference(a, LibDecimalFloat.FLOAT_HALF, this.sqrtExternal(a), "sqrt");
    }

    function testSqrtSquare(int224 coefficient, int32 exponent, uint8 region) external {
        assertSqrtSquare(positive(coefficient, exponent, region));
    }

    function testSqrtMonotone(int224 coefficient, int32 exponent, uint8 region, uint256 step) external {
        Float a = positive(coefficient, exponent, region);
        Float error = LibTestErrorBound.pow(LibDecimalFloat.FLOAT_HALF);
        assertTrue(
            LibTestErrorBound.monotoneRelative(this.sqrtExternal(a), this.sqrtExternal(stepUp(a, step)), error, error),
            "sqrt monotone"
        );
    }
}
