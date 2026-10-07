// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float, ExponentUnderflow} from "src/lib/LibDecimalFloat.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";
import {LibTranscendentalOracle} from "test/lib/LibTranscendentalOracle.sol";
import {LibTestErrorBound} from "test/lib/LibTestErrorBound.sol";

/// log10, pow10, pow and sqrt against the `bc` constant oracle, within 1e-67,
/// and against each other, each within the proven bound LibTestErrorBound
/// gives it.
contract LibDecimalFloatPrecisionTest is Test {
    using LibDecimalFloat for Float;

    function log10External(Float a) external pure returns (Float) {
        return a.log10();
    }

    function pow10External(Float a) external pure returns (Float) {
        return a.pow10();
    }

    function powExternal(Float a, Float b) external pure returns (Float) {
        return a.pow(b);
    }

    function sqrtExternal(Float a) external pure returns (Float) {
        return a.sqrt();
    }

    function assertWithin(int256 errorCoefficient, int256 errorExponent, Float bound, string memory what)
        internal
        pure
    {
        (int256 boundCoefficient, int256 boundExponent) = bound.unpack();
        assertTrue(LibTestExactDecimal.absLte(errorCoefficient, errorExponent, boundCoefficient, boundExponent), what);
    }

    function cmp(Float a, Float b) internal pure returns (int256) {
        (int256 ca, int256 ea) = a.unpack();
        (int256 cb, int256 eb) = b.unpack();
        return LibTestExactDecimal.cmpParts(ca, ea, cb, eb);
    }

    /// actual / expected - 1, unpacked.
    function relativeError(int256 ca, int256 ea, Float expected) internal pure returns (int256, int256) {
        (int256 cb, int256 eb) = expected.unpack();
        (ca, ea) = LibTestExactDecimal.quotient(ca, ea, cb, eb);
        return LibTestExactDecimal.minusOne(ca, ea);
    }

    function relativeError(Float actual, Float expected) internal pure returns (int256, int256) {
        (int256 ca, int256 ea) = actual.unpack();
        return relativeError(ca, ea, expected);
    }

    /// actual / (power 10^exponent) - 1, unpacked.
    function relativeError(Float actual, uint256 power, int256 exponent) internal pure returns (int256, int256) {
        (int256 signedCoefficient, int256 actualExponent) = actual.unpack();
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedPower = int256(power);
        (signedCoefficient, actualExponent) =
            LibTestExactDecimal.quotient(signedCoefficient, actualExponent, signedPower, exponent);
        return LibTestExactDecimal.minusOne(signedCoefficient, actualExponent);
    }

    /// The floor's term relative to the oracle's power, which is within 1e-67
    /// of the true value, so the term is within 1e-67 of itself.
    function floorOf(uint256 power, int256 powerExponent) internal pure returns (Float) {
        // The oracle's power is below 1e71 and so fits.
        // forge-lint: disable-next-line(unsafe-typecast)
        return LibTestErrorBound.floor(int256(power), powerExponent);
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
        (int256 signedCoefficient, int256 exponent) = b.unpack();
        // forge-lint: disable-next-line(unsafe-typecast)
        (signedCoefficient, exponent) =
            LibTestExactDecimal.mulParts(int256(LibTestExactDecimal.abs(signedCoefficient)), exponent, 3, -67);
        (Float slack,) = LibDecimalFloat.packLossy(signedCoefficient, exponent);
        return LibTestErrorBound.plus(slack, LibDecimalFloat.packLossless(2, -65));
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

    /// The largest x below which every 10^x packs: an integer x returns
    /// 10^x as 1 at exponent x.
    int256 constant POW10_TOP = type(int32).max;

    /// x scaled to a coefficient at exponent, toward zero, held to int224.
    function exponentLimit(uint256 magnitude, int256 exponent) internal pure returns (int256) {
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
        return int256(limit);
    }

    /// A float x of magnitude below 10^digits with any exponent in [-90, 2],
    /// across the whole range where 10^x packs: above int32.min, where it
    /// underflows, and at most `POW10_TOP`.
    function exponentInput(int256 coefficient, int256 exponent, uint256 digits) internal pure returns (Float) {
        exponent = bound(exponent, -90, 2);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 magnitude = 10 ** bound(digits, 0, 10);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 bottom = uint256(-int256(type(int32).min)) - 1;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 top = uint256(POW10_TOP);
        coefficient = bound(
            coefficient,
            -exponentLimit(magnitude < bottom ? magnitude : bottom, exponent),
            exponentLimit(magnitude < top ? magnitude : top, exponent)
        );
        return LibDecimalFloat.packLossless(coefficient, exponent);
    }

    /// log10 a from the oracle as characteristic + fraction / 1e70, unpacked.
    function oracleLog10(Float a) internal pure returns (int256, int256) {
        (int256 signedCoefficient, int256 exponent) = a.unpack();
        // a is positive.
        // forge-lint: disable-next-line(unsafe-typecast)
        (int256 characteristic, uint256 fraction) = LibTranscendentalOracle.log10(uint256(signedCoefficient), exponent);
        // forge-lint: disable-next-line(unsafe-typecast)
        return LibTestExactDecimal.addParts(characteristic, 0, int256(fraction), -70);
    }

    /// log10 a within half a unit plus `DOCUMENTED_LOG10_RAW_ERROR` units of 1e-50, plus
    /// the oracle's 1e-67.
    function assertLog10Reference(Float a, string memory what) internal view {
        Float actual = this.log10External(a);
        (int256 actualCoefficient, int256 actualExponent) = actual.unpack();
        (int256 expectedCoefficient, int256 expectedExponent) = oracleLog10(a);
        (int256 errorCoefficient, int256 errorExponent) =
            LibTestExactDecimal.subParts(actualCoefficient, actualExponent, expectedCoefficient, expectedExponent);
        assertWithin(
            errorCoefficient,
            errorExponent,
            LibTestErrorBound.plus(LibTestErrorBound.log10(a), LibDecimalFloat.packLossless(1, -67)),
            what
        );
    }

    function assertPow10Reference(Float x, Float actual, string memory what) internal pure {
        (int256 signedCoefficient, int256 exponent) = x.unpack();
        (uint256 power, int256 powerExponent) = LibTranscendentalOracle.exp10(signedCoefficient, exponent);
        (int256 errorCoefficient, int256 errorExponent) = relativeError(actual, power, powerExponent);
        assertWithin(
            errorCoefficient,
            errorExponent,
            LibTestErrorBound.plus(
                LibTestErrorBound.plus(LibTestErrorBound.pow10(), floorOf(power, powerExponent)), exp10Slack()
            ),
            what
        );
    }

    /// 10^(b log10 a) from the oracle.
    function oraclePow(Float a, Float b) internal pure returns (uint256, int256) {
        (int256 logCoefficient, int256 logExponent) = oracleLog10(a);
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (int256 signedCoefficient, int256 exponent) =
            LibTestExactDecimal.mulParts(signedCoefficientB, exponentB, logCoefficient, logExponent);
        return LibTranscendentalOracle.exp10(signedCoefficient, exponent);
    }

    /// a^b within LibTestErrorBound.pow(b) of 10^(b log10 a) from the oracle.
    function assertPowReference(Float a, Float b, Float actual, string memory what) internal pure {
        (uint256 power, int256 powerExponent) = oraclePow(a, b);
        (int256 errorCoefficient, int256 errorExponent) = relativeError(actual, power, powerExponent);
        assertWithin(
            errorCoefficient,
            errorExponent,
            LibTestErrorBound.plus(
                LibTestErrorBound.plus(LibTestErrorBound.pow(b), floorOf(power, powerExponent)), powSlack(b)
            ),
            what
        );
    }

    /// The product's packing moves its log by under 4.4e-67, and each
    /// `subParts` of logs at most 280 truncates under a unit of a maximized
    /// coefficient above 5.7e75, so under 4.9e-74.
    function log10ProductSlack() internal pure returns (Float) {
        return LibDecimalFloat.packLossless(1, -66);
    }

    /// The `quotient` near 1 truncates under 2e-74 and `mulParts` under
    /// 2e-76 relative.
    function packingSlack() internal pure returns (Float) {
        return LibDecimalFloat.packLossless(1, -73);
    }

    /// |log10(a b) - log10 a - log10 b| within the three logs' bounds.
    function assertLog10Product(Float a, Float b) internal view {
        (int256 logA, int256 exponentA) = this.log10External(a).unpack();
        (int256 logB, int256 exponentB) = this.log10External(b).unpack();
        Float product = a.mul(b);
        (int256 errorCoefficient, int256 errorExponent) = this.log10External(product).unpack();
        (errorCoefficient, errorExponent) =
            LibTestExactDecimal.subParts(errorCoefficient, errorExponent, logA, exponentA);
        (errorCoefficient, errorExponent) =
            LibTestExactDecimal.subParts(errorCoefficient, errorExponent, logB, exponentB);
        Float bound = LibTestErrorBound.plus(LibTestErrorBound.log10(product), LibTestErrorBound.log10(a));
        bound = LibTestErrorBound.plus(bound, LibTestErrorBound.log10(b));
        assertWithin(
            errorCoefficient, errorExponent, LibTestErrorBound.plus(bound, log10ProductSlack()), "log10 product"
        );
    }

    /// pow10(log10 a) / a - 1. The log is within E of log10 a, which moves
    /// the power by under 2.3027 E relative for E below 1e-30.
    function assertPow10Log10(Float a) internal view {
        Float log = this.log10External(a);
        (int256 errorCoefficient, int256 errorExponent) = relativeError(this.pow10External(log), a);
        Float bound = LibTestErrorBound.times(LibTestErrorBound.log10(a), LibDecimalFloat.packLossless(23027, -4));
        bound = LibTestErrorBound.plus(LibTestErrorBound.pow10(), bound);
        assertWithin(errorCoefficient, errorExponent, LibTestErrorBound.plus(bound, packingSlack()), "pow10 log10");
    }

    /// pow(a, b) pow(a, c) / pow(a, b + c) - 1, within the three powers'
    /// bounds. Packing b + c moves the exponent by under 1e-66 of it, at most
    /// 2e6 times log10 a at most 210, so the power by under 1e-57.
    function assertPowProduct(Float a, Float b, Float c) internal view {
        Float sum = b.add(c);
        (int256 powerB, int256 exponentB) = this.powExternal(a, b).unpack();
        (int256 powerC, int256 exponentC) = this.powExternal(a, c).unpack();
        (powerB, exponentB) = LibTestExactDecimal.mulParts(powerB, exponentB, powerC, exponentC);
        (int256 errorCoefficient, int256 errorExponent) = relativeError(powerB, exponentB, this.powExternal(a, sum));
        Float bound = LibTestErrorBound.plus(LibTestErrorBound.pow(b), LibTestErrorBound.pow(c));
        bound = LibTestErrorBound.plus(bound, LibTestErrorBound.pow(sum));
        assertWithin(
            errorCoefficient,
            errorExponent,
            LibTestErrorBound.plus(bound, LibDecimalFloat.packLossless(2, -57)),
            "pow product"
        );
    }

    /// sqrt(a)^2 / a - 1, within twice the root's bound plus its square.
    function assertSqrtSquare(Float a) internal view {
        (int256 root, int256 rootExponent) = this.sqrtExternal(a).unpack();
        (root, rootExponent) = LibTestExactDecimal.mulParts(root, rootExponent, root, rootExponent);
        (int256 errorCoefficient, int256 errorExponent) = relativeError(root, rootExponent, a);
        Float error = LibTestErrorBound.sqrt();
        Float bound =
            LibTestErrorBound.plus(LibTestErrorBound.plus(error, error), LibTestErrorBound.times(error, error));
        assertWithin(errorCoefficient, errorExponent, LibTestErrorBound.plus(bound, packingSlack()), "sqrt square");
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
    function testPow10Grid() external view {
        Float previous = LibDecimalFloat.FLOAT_ZERO;
        for (uint256 idx = 0; idx < 10000; idx++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            Float x = LibDecimalFloat.packLossless(int256(idx), -4);
            Float actual = this.pow10External(x);
            assertTrue(cmp(actual, previous) > 0, "pow10 grid increasing");
            previous = actual;
            assertPow10Reference(x, actual, "pow10 grid");
        }
    }

    /// log10 is non decreasing over every four digit mantissa. Neighbours'
    /// logs differ by over 4.3e-5, far above twice its error bound.
    function testLog10GridMonotone() external view {
        Float previous = this.log10External(LibDecimalFloat.packLossless(1000, 0));
        for (uint256 n = 1001; n < 10000; n++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            Float actual = this.log10External(LibDecimalFloat.packLossless(int256(n), 0));
            assertTrue(cmp(actual, previous) >= 0, "log10 grid monotone");
            previous = actual;
        }
    }

    function testLog10Reference(int224 coefficient, int32 exponent, uint8 region) external view {
        assertLog10Reference(positive(coefficient, exponent, region), "log10");
    }

    /// log10 a three units of the 41st digit inside a power of ten in
    /// magnitude, where the true log's unit is a tenth of the power's. The
    /// logs, from `bc -l`, are within 1e-66 of 1 - 3e-41, -1 + 3e-41 and
    /// 10 - 3e-40.
    function testLog10ReferenceInsidePowersOfTen() external view {
        assertLog10Reference(
            LibDecimalFloat.packLossless(9999999999999999999999999999999999999999309224472101786294794602563, -66),
            "inside 1"
        );
        assertLog10Reference(
            LibDecimalFloat.packLossless(1000000000000000000000000000000000000000069077552789821370520539743, -67),
            "inside -1"
        );
        assertLog10Reference(
            LibDecimalFloat.packLossless(9999999999999999999999999999999999999993092244721017862947946025635, -57),
            "inside 10"
        );
    }

    /// log10(10^k) is exactly k, for every k a Float can hold, whatever power
    /// of ten carries it.
    function testLog10Anchors(int32 k, uint8 digits) external view {
        int256 shift = int256(bound(digits, 0, 66));
        int256 exponent = bound(k, int256(type(int32).min), int256(type(int32).max) - shift);
        // forge-lint: disable-next-line(unsafe-typecast)
        Float a = LibDecimalFloat.packLossless(int256(10 ** uint256(shift)), exponent);
        assertTrue(cmp(this.log10External(a), LibDecimalFloat.packLossless(exponent + shift, 0)) == 0, "log10 anchor");
    }

    function assertLog10Monotone(Float a, Float b, string memory what) internal view {
        Float low = this.log10External(a);
        Float high = this.log10External(b);
        assertTrue(
            LibTestErrorBound.monotoneAbsolute(low, high, LibTestErrorBound.log10(a), LibTestErrorBound.log10(b)), what
        );
    }

    function testLog10Monotone(int224 coefficient, int32 exponent, uint8 region, uint256 step) external view {
        Float a = positive(coefficient, exponent, region);
        assertLog10Monotone(a, stepUp(a, step), "log10 monotone");
    }

    function testLog10MonotonePairs(
        int224 coefficientA,
        int32 exponentA,
        int224 coefficientB,
        int32 exponentB,
        uint8 region
    ) external view {
        Float a = positive(coefficientA, exponentA, region);
        Float b = positive(coefficientB, exponentB, region);
        if (a.gt(b)) {
            (a, b) = (b, a);
        }
        assertLog10Monotone(a, b, "log10 monotone pairs");
    }

    function testLog10Product(int224 coefficientA, int32 exponentA, int224 coefficientB, int32 exponentB)
        external
        view
    {
        Float a = positive(coefficientA, exponentA, 0);
        Float b = positive(coefficientB, exponentB, 0);
        assertLog10Product(a, b);
    }

    function testPow10Reference(int256 coefficient, int256 exponent, uint256 digits) external view {
        Float x = exponentInput(coefficient, exponent, digits);
        assertPow10Reference(x, this.pow10External(x), "pow10");
    }

    /// pow10(k) is exactly 10^k for every whole k whose power packs.
    function testPow10Anchors(int32 k) external view {
        assertTrue(
            cmp(this.pow10External(LibDecimalFloat.packLossless(k, 0)), LibDecimalFloat.packLossless(1, k)) == 0,
            "pow10 anchor"
        );
    }

    function assertPow10Monotone(Float x, Float y, string memory what) internal view {
        assertTrue(
            LibTestErrorBound.monotoneRelative(
                this.pow10External(x), this.pow10External(y), LibTestErrorBound.pow10(), LibTestErrorBound.pow10()
            ),
            what
        );
    }

    function testPow10Monotone(int256 coefficient, int256 exponent, uint256 digits, uint256 step) external view {
        Float x = exponentInput(coefficient, exponent, digits);
        Float y = stepUp(x, step).min(LibDecimalFloat.packLossless(POW10_TOP, 0));
        assertPow10Monotone(x, y, "pow10 monotone");
    }

    function testPow10MonotonePairs(int256 coefficientX, int256 coefficientY, int256 exponent, uint256 digits)
        external
        view
    {
        Float x = exponentInput(coefficientX, exponent, digits);
        Float y = exponentInput(coefficientY, exponent, digits);
        if (x.gt(y)) {
            (x, y) = (y, x);
        }
        assertPow10Monotone(x, y, "pow10 monotone pairs");
    }

    function testPow10Log10(int224 coefficient, int32 exponent) external view {
        Float a = positive(coefficient, exponent, 0);
        assertPow10Log10(a);
    }

    function testPowReference(int224 coefficientA, int32 exponentA, uint8 region, int256 coefficientB, int256 exponentB)
        external
        view
    {
        (Float a, Float b) = powInputs(coefficientA, exponentA, region, coefficientB, exponentB);
        assertPowReference(a, b, this.powExternal(a, b), "pow");
    }

    /// a^b for b in [1, 2] with a placed so b log10 a is within a few units
    /// of [-2147483660, -2147483600], across the floor region: within the
    /// proven bound plus the floor's 1e-2147483648 absolute, or reverting
    /// `ExponentUnderflow` only for a true value below 1e-2147483648.
    function testPowFloor(int256 coefficientA, int256 target, int256 coefficientB) external view {
        coefficientA = bound(coefficientA, 1, 1e67);
        target = bound(target, -2147483660, -2147483600);
        coefficientB = bound(coefficientB, 1e18, 2e18);
        int256 digits = 1;
        for (int256 scale = 10; scale <= coefficientA; scale *= 10) {
            digits++;
        }
        int256 exponentA = target * 1e18 / coefficientB - (digits - 1);
        if (exponentA < type(int32).min) {
            exponentA = type(int32).min;
        }
        Float a = LibDecimalFloat.packLossless(coefficientA, exponentA);
        Float b = LibDecimalFloat.packLossless(coefficientB, -18);
        try this.powExternal(a, b) returns (Float actual) {
            assertPowReference(a, b, actual, "pow floor");
        } catch (bytes memory reason) {
            // forge-lint: disable-next-line(unsafe-typecast)
            assertEq(bytes4(reason), ExponentUnderflow.selector);
            (uint256 power, int256 powerExponent) = oraclePow(a, b);
            // The oracle's power is below 1e71 and so fits.
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 signedPower = int256(power);
            assertTrue(
                LibTestExactDecimal.cmpParts(
                    signedPower, powerExponent, 100000000000000000000000000000000000000001, -2147483688
                ) < 0,
                "underflow below the floor"
            );
        }
    }

    function testPowProduct(
        int224 coefficientA,
        int32 exponentA,
        int256 coefficientB,
        int256 coefficientC,
        int256 exponentB
    ) external view {
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
    ) external view {
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

    function testSqrtReference(int224 coefficient, int32 exponent, uint8 region) external view {
        Float a = positive(coefficient, exponent, region);
        assertPowReference(a, LibDecimalFloat.FLOAT_HALF, this.sqrtExternal(a), "sqrt");
    }

    function testSqrtSquare(int224 coefficient, int32 exponent, uint8 region) external view {
        assertSqrtSquare(positive(coefficient, exponent, region));
    }

    function testSqrtMonotone(int224 coefficient, int32 exponent, uint8 region, uint256 step) external view {
        Float a = positive(coefficient, exponent, region);
        assertTrue(cmp(this.sqrtExternal(a), this.sqrtExternal(stepUp(a, step))) <= 0, "sqrt monotone");
    }
}
