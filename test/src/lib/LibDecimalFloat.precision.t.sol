// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibExactFloat} from "test/lib/LibExactFloat.sol";
import {LibTestErrorBound} from "test/lib/LibTestErrorBound.sol";
import {LibTestPowRange, PowRange, Log10} from "test/lib/LibTestPowRange.sol";

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
        assertTrue(
            LibExactFloat.cmpScaled(
                LibExactFloat.u512(LibExactFloat.abs(errorCoefficient)),
                errorExponent,
                LibExactFloat.u512(LibExactFloat.abs(boundCoefficient)),
                boundExponent
            ) <= 0,
            what
        );
    }

    /// |Σ cᵢ 10^eᵢ| within the bound, exactly.
    function assertWithinSum(int256[] memory coefficients, int256[] memory exponents, Float bound, string memory what)
        internal
        pure
    {
        int256[] memory boundCoefficients = new int256[](1);
        int256[] memory boundExponents = new int256[](1);
        (boundCoefficients[0], boundExponents[0]) = bound.unpack();
        assertTrue(LibExactFloat.absSumLte(coefficients, exponents, boundCoefficients, boundExponents), what);
    }

    function cmp(Float a, Float b) internal pure returns (int256) {
        (int256 ca, int256 ea) = a.unpack();
        (int256 cb, int256 eb) = b.unpack();
        return LibExactFloat.cmpParts(ca, ea, cb, eb);
    }

    /// actual / expected - 1, unpacked.
    function relativeError(int256 ca, int256 ea, Float expected) internal pure returns (int256, int256) {
        (int256 cb, int256 eb) = expected.unpack();
        (ca, ea) = LibExactFloat.quotient(ca, ea, cb, eb);
        (, ca, ea) = LibExactFloat.addPartsWide(ca, ea, -1, 0);
        return (ca, ea);
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
            LibExactFloat.quotient(signedCoefficient, actualExponent, signedPower, exponent);
        (, signedCoefficient, actualExponent) = LibExactFloat.addPartsWide(signedCoefficient, actualExponent, -1, 0);
        return (signedCoefficient, actualExponent);
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

    /// log10 a within half a unit plus `LOG10_RAW_ERROR_E54` units of 1e-54, plus
    /// the oracle's 1e-67.
    function assertLog10Reference(Float a, string memory what) internal view {
        (int256 signedCoefficient, int256 exponent) = a.unpack();
        // a is positive.
        // forge-lint: disable-next-line(unsafe-typecast)
        (int256 characteristic, uint256 fraction) = LibExactFloat.log10(uint256(signedCoefficient), exponent);
        int256[] memory coefficients = new int256[](3);
        int256[] memory exponents = new int256[](3);
        (coefficients[0], exponents[0]) = this.log10External(a).unpack();
        (coefficients[1], exponents[1]) = (-characteristic, 0);
        // forge-lint: disable-next-line(unsafe-typecast)
        (coefficients[2], exponents[2]) = (-int256(fraction), -70);
        assertWithinSum(
            coefficients,
            exponents,
            LibTestErrorBound.plus(LibTestErrorBound.log10(a), LibDecimalFloat.packLossless(1, -67)),
            what
        );
    }

    function assertPow10Reference(Float x, Float actual, string memory what) internal pure {
        (int256 signedCoefficient, int256 exponent) = x.unpack();
        (uint256 power, int256 powerExponent) = LibExactFloat.exp10(signedCoefficient, exponent);
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

    /// 10^(b log10 a) from the oracle, and its relative error. log10 a is
    /// `LibTestPowRange.log10Abs`'s low bound, within 6e-69 relative within
    /// 1e-3 of one and 1e-67 absolute elsewhere, so y = b log10 a is within
    /// 6e-69 |y| or 1e-67 |b|, plus 2 |y| 1e-75 from the 76 digit sum and
    /// product, at most 4.3e-66 for |y| up to 2.15e9. 10^y moves by ln 10 of
    /// that, and the oracle's power and the quotient add 1e-67 each.
    function oraclePow(Float a, Float b) internal pure returns (uint256 power, int256 powerExponent, Float slack) {
        if (cmp(a, LibDecimalFloat.FLOAT_ONE) == 0) {
            (power, powerExponent) = LibExactFloat.exp10(0, 0);
            return (power, powerExponent, LibDecimalFloat.packLossless(2, -65));
        }
        (int256 signedCoefficient, int256 exponent) = a.unpack();
        Log10 memory log = LibTestPowRange.log10Abs(signedCoefficient, exponent);
        // whole is below 3e9 and the fraction below 1e76.
        (, int256 logCoefficient, int256 logExponent) = LibExactFloat.addPartsWide(
            // forge-lint: disable-next-line(unsafe-typecast)
            int256(log.whole),
            0,
            // forge-lint: disable-next-line(unsafe-typecast)
            int256(log.lowFraction),
            log.fractionExponent
        );
        if (log.negative) {
            logCoefficient = -logCoefficient;
        }
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (signedCoefficient, exponent) =
            LibExactFloat.mulPayload(signedCoefficientB, exponentB, logCoefficient, logExponent);
        (power, powerExponent) = LibExactFloat.exp10(signedCoefficient, exponent);
        int256 slackCoefficient;
        int256 slackExponent;
        if (log.nearOne) {
            (slackCoefficient, slackExponent) = LibExactFloat.mulPayload(
                // forge-lint: disable-next-line(unsafe-typecast)
                int256(LibExactFloat.abs(signedCoefficient)),
                exponent,
                14,
                -69
            );
        } else {
            (slackCoefficient, slackExponent) = LibExactFloat.mulPayload(
                // forge-lint: disable-next-line(unsafe-typecast)
                int256(LibExactFloat.abs(signedCoefficientB)),
                exponentB,
                3,
                -67
            );
        }
        (slack,) = LibDecimalFloat.packLossy(slackCoefficient, slackExponent);
        slack = LibTestErrorBound.plus(slack, LibDecimalFloat.packLossless(2, -65));
    }

    /// a^b within LibTestErrorBound.pow(a, b) of 10^(b log10 a) from the oracle.
    function assertPowReference(Float a, Float b, Float actual, string memory what) internal pure {
        (uint256 power, int256 powerExponent, Float limit) = oraclePow(a, b);
        limit = LibTestErrorBound.plus(
            LibTestErrorBound.plus(limit, LibTestErrorBound.pow(a, b)), floorOf(power, powerExponent)
        );
        (int256 errorCoefficient, int256 errorExponent) = relativeError(actual, power, powerExponent);
        assertWithin(errorCoefficient, errorExponent, limit, what);
    }

    /// The product's packing moves its log by under 4.4e-67.
    function log10ProductSlack() internal pure returns (Float) {
        return LibDecimalFloat.packLossless(1, -66);
    }

    /// The `quotient` near 1 truncates under 1e-74, `mulPayload` under 2e-76
    /// relative, and their products with the bounds under 1e-76.
    function packingSlack() internal pure returns (Float) {
        return LibDecimalFloat.packLossless(103, -76);
    }

    /// |log10(a b) - log10 a - log10 b| within the three logs' bounds.
    function assertLog10Product(Float a, Float b) internal view {
        Float product = a.mul(b);
        int256[] memory coefficients = new int256[](3);
        int256[] memory exponents = new int256[](3);
        (coefficients[0], exponents[0]) = this.log10External(product).unpack();
        (coefficients[1], exponents[1]) = this.log10External(a).unpack();
        (coefficients[2], exponents[2]) = this.log10External(b).unpack();
        (coefficients[1], coefficients[2]) = (-coefficients[1], -coefficients[2]);
        Float bound = LibTestErrorBound.plus(LibTestErrorBound.log10(product), LibTestErrorBound.log10(a));
        bound = LibTestErrorBound.plus(bound, LibTestErrorBound.log10(b));
        assertWithinSum(coefficients, exponents, LibTestErrorBound.plus(bound, log10ProductSlack()), "log10 product");
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
    /// bounds. Packing b + c moves the exponent by under 1e-66 of it, and
    /// |(b + c) log10 a| is at most 2e9, so the power by under 4.7e-57.
    function assertPowProduct(Float a, Float b, Float c) internal view {
        Float sum = b.add(c);
        (int256 powerB, int256 exponentB) = this.powExternal(a, b).unpack();
        (int256 powerC, int256 exponentC) = this.powExternal(a, c).unpack();
        (powerB, exponentB) = LibExactFloat.mulPayload(powerB, exponentB, powerC, exponentC);
        (int256 errorCoefficient, int256 errorExponent) = relativeError(powerB, exponentB, this.powExternal(a, sum));
        Float bound = LibTestErrorBound.plus(LibTestErrorBound.pow(a, b), LibTestErrorBound.pow(a, c));
        bound = LibTestErrorBound.plus(bound, LibTestErrorBound.pow(a, sum));
        assertWithin(
            errorCoefficient,
            errorExponent,
            LibTestErrorBound.plus(bound, LibDecimalFloat.packLossless(5, -57)),
            "pow product"
        );
    }

    /// sqrt(a)^2 / a - 1, within twice the root's bound plus its square.
    function assertSqrtSquare(Float a) internal view {
        (int256 root, int256 rootExponent) = this.sqrtExternal(a).unpack();
        (root, rootExponent) = LibExactFloat.mulPayload(root, rootExponent, root, rootExponent);
        (int256 errorCoefficient, int256 errorExponent) = relativeError(root, rootExponent, a);
        Float error = LibTestErrorBound.sqrt();
        Float bound =
            LibTestErrorBound.plus(LibTestErrorBound.plus(error, error), LibTestErrorBound.times(error, error));
        assertWithin(errorCoefficient, errorExponent, LibTestErrorBound.plus(bound, packingSlack()), "sqrt square");
    }

    /// A positive base, `positive` or for region 3 within 1e-3 of one, and a
    /// power at exponent -76 to 10 with |b log10 a| at most 1e9, by
    /// `powLimit`, so a^b packs, and a^(b + c) for two of them. Near one |b|
    /// reaches past 1e75.
    function powInputs(int224 coefficientA, int32 exponentA, uint8 region, int256 coefficientB, int256 exponentB)
        internal
        pure
        returns (Float a, Float b)
    {
        a = region % 4 == 3 ? nearOne(coefficientA, exponentA) : positive(coefficientA, exponentA, region);
        exponentB = bound(exponentB, -76, 10);
        int256 limit = powLimit(a, exponentB);
        coefficientB = bound(coefficientB, -limit, limit);
        b = LibDecimalFloat.packLossless(coefficientB, exponentB);
    }

    /// 10^j -+ k at exponent -j, for j in [3, 66] and k in [1, 10^(j - 3)]
    /// with a digit count of its own, so d = |a - 1| runs from 1e-66 to 1e-3.
    function nearOne(int224 coefficient, int32 exponent) internal pure returns (Float) {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 seed = uint256(uint32(exponent));
        uint256 j = 3 + seed % 64;
        uint256 m = (seed >> 8) % (j - 2);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 magnitude = coefficient < 0 ? uint256(-int256(coefficient)) : uint256(int256(coefficient));
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 k = int256(magnitude % 10 ** m + 1);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 unit = int256(10 ** j);
        // forge-lint: disable-next-line(unsafe-typecast)
        return LibDecimalFloat.packLossless(coefficient < 0 ? unit - k : unit + k, -int256(j));
    }

    /// The largest coefficient at `exponent` with |b log10 a| at most 1e9,
    /// over |log10 a|'s high bound from `LibTestPowRange.log10Abs`, rounded
    /// down and held to int224.
    function powLimit(Float a, int256 exponent) internal pure returns (int256) {
        if (cmp(a, LibDecimalFloat.FLOAT_ONE) == 0) {
            return type(int224).max;
        }
        (int256 signedCoefficient, int256 aExponent) = a.unpack();
        Log10 memory log = LibTestPowRange.log10Abs(signedCoefficient, aExponent);
        (, int256 logCoefficient, int256 logExponent) = LibExactFloat.addPartsWide(
            // forge-lint: disable-next-line(unsafe-typecast)
            int256(log.whole),
            0,
            // forge-lint: disable-next-line(unsafe-typecast)
            int256(log.highFraction),
            log.fractionExponent
        );
        (int256 limit, int256 limitExponent) = LibExactFloat.quotient(1, 9 - exponent, logCoefficient, logExponent);
        if (limitExponent >= 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            if (limitExponent > 66 || limit > type(int224).max / int256(10 ** uint256(limitExponent))) {
                return type(int224).max;
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            return limit * int256(10 ** uint256(limitExponent));
        }
        if (limitExponent < -76) {
            return 0;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        limit /= int256(10 ** uint256(-limitExponent));
        return limit > type(int224).max ? type(int224).max : limit;
    }

    function freeMemoryPointer() internal pure returns (uint256) {
        uint256 pointer;
        assembly ("memory-safe") {
            pointer := mload(0x40)
        }
        return pointer;
    }

    /// Frees what a grid step allocated. Only stack values cross steps.
    function reclaim(uint256 pointer) internal pure {
        assembly ("memory-safe") {
            mstore(0x40, pointer)
        }
    }

    /// pow10 over antilog table inputs x = idx / 1e4 for idx in [start, end),
    /// each above the previous index's. Neighbours differ by 2.3e-4 relative,
    /// far above the 41 digit rounding, so the grid strictly increases.
    function checkPow10Grid(uint256 start, uint256 end) internal view {
        Float previous = start == 0
            ? LibDecimalFloat.FLOAT_ZERO
            // forge-lint: disable-next-line(unsafe-typecast)
            : this.pow10External(LibDecimalFloat.packLossless(int256(start - 1), -4));
        uint256 pointer = freeMemoryPointer();
        for (uint256 idx = start; idx < end; idx++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            Float x = LibDecimalFloat.packLossless(int256(idx), -4);
            Float actual = this.pow10External(x);
            assertTrue(cmp(actual, previous) > 0, "pow10 grid increasing");
            previous = actual;
            assertPow10Reference(x, actual, "pow10 grid");
            reclaim(pointer);
        }
    }

    /// The four slices cover idx 0-9999, each under the call gas limit.
    function testPow10Grid0() external view {
        checkPow10Grid(0, 2500);
    }

    function testPow10Grid1() external view {
        checkPow10Grid(2500, 5000);
    }

    function testPow10Grid2() external view {
        checkPow10Grid(5000, 7500);
    }

    function testPow10Grid3() external view {
        checkPow10Grid(7500, 10000);
    }

    /// log10 is non decreasing over every four digit mantissa. Neighbours'
    /// logs differ by over 4.3e-5, far above twice its error bound.
    function testLog10GridMonotone() external view {
        Float previous = this.log10External(LibDecimalFloat.packLossless(1000, 0));
        uint256 pointer = freeMemoryPointer();
        for (uint256 n = 1001; n < 10000; n++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            Float actual = this.log10External(LibDecimalFloat.packLossless(int256(n), 0));
            assertTrue(cmp(actual, previous) >= 0, "log10 grid monotone");
            previous = actual;
            reclaim(pointer);
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
    /// proven bound plus the floor's 1e-2147483648 absolute where it returns,
    /// and returning or reverting `ExponentUnderflow` as
    /// `LibTestPowRange.powRange` decides.
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
        PowRange range = LibTestPowRange.powRange(a, b);
        try this.powExternal(a, b) returns (Float actual) {
            assertTrue(LibTestPowRange.mayReturn(range), "returned below the floor");
            assertPowReference(a, b, actual, "pow floor");
        } catch (bytes memory reason) {
            assertTrue(LibTestPowRange.mayRevert(range, false), "underflow above the floor");
            assertEq(reason, LibTestPowRange.rangeError(false, a));
            (uint256 power, int256 powerExponent,) = oraclePow(a, b);
            // The oracle's power is below 1e71 and so fits.
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 signedPower = int256(power);
            assertTrue(
                LibExactFloat.cmpParts(
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

    /// For a fixed positive power, pow is non decreasing in the base. b is
    /// held to `powLimit` of both bases, so both powers pack.
    function testPowMonotoneInBase(
        int224 coefficientA,
        int32 exponentA,
        uint256 step,
        int256 coefficientB,
        int256 exponentB
    ) external view {
        Float a = positive(coefficientA, exponentA, 0);
        Float c = stepUp(a, step);
        exponentB = bound(exponentB, -76, 10);
        int256 limit = powLimit(a, exponentB);
        int256 limitC = powLimit(c, exponentB);
        Float b = LibDecimalFloat.packLossless(bound(coefficientB, 0, limit < limitC ? limit : limitC), exponentB);
        assertTrue(
            LibTestErrorBound.monotoneRelative(
                this.powExternal(a, b), this.powExternal(c, b), LibTestErrorBound.pow(a, b), LibTestErrorBound.pow(c, b)
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
