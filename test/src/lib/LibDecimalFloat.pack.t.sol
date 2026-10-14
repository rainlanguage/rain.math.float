// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, ExponentOverflow, Float} from "../../../src/lib/LibDecimalFloat.sol";
import {LibExactFloat} from "../../lib/LibExactFloat.sol";
import {LossyConversionToFloat} from "../../../src/error/ErrDecimalFloat.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";

contract LibDecimalFloatPackTest is Test {
    function packLossyExternal(int256 signedCoefficient, int256 exponent) external pure returns (Float, bool) {
        return LibDecimalFloat.packLossy(signedCoefficient, exponent);
    }

    function unpackExternal(Float float) external pure returns (int256, int256) {
        return LibDecimalFloat.unpack(float);
    }

    /// Round trip from/to parts.
    function testPartsRoundTrip(int224 signedCoefficient, int32 exponent) external pure {
        (Float float, bool lossless) = LibDecimalFloat.packLossy(signedCoefficient, exponent);
        (int256 signedCoefficientOut, int256 exponentOut) = LibDecimalFloat.unpack(float);

        assertTrue(lossless, "lossless");
        assertEq(signedCoefficient, signedCoefficientOut, "coefficient");
        assertEq(signedCoefficient == 0 ? int256(0) : exponent, exponentOut, "exponent");
    }

    /// `unpack` then `packLossy` is the identity, byte for byte and lossless,
    /// on every Float with a non-zero coefficient.
    function testUnpackPackLossyRoundTrip(Float float) external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.unpack(float);
        vm.assume(signedCoefficient != 0);
        (Float repacked, bool lossless) = LibDecimalFloat.packLossy(signedCoefficient, exponent);
        assertTrue(lossless, "lossless");
        assertEq(Float.unwrap(repacked), Float.unwrap(float), "bytes");
    }

    /// Zero at any exponent unpacks to a zero coefficient at that exponent
    /// and repacks as `FLOAT_ZERO`, the one Float the round trip rewrites.
    function testUnpackPackLossyZeroAtAnyExponent(uint32 exponent) external pure {
        Float zero = Float.wrap(bytes32(uint256(exponent) << 224));
        (int256 signedCoefficient, int256 unpackedExponent) = LibDecimalFloat.unpack(zero);
        assertEq(signedCoefficient, 0, "coefficient");
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(unpackedExponent, int256(int32(exponent)), "exponent");
        (Float repacked, bool lossless) = LibDecimalFloat.packLossy(signedCoefficient, unpackedExponent);
        assertTrue(lossless, "lossless");
        assertEq(Float.unwrap(repacked), Float.unwrap(LibDecimalFloat.FLOAT_ZERO), "float");
    }

    /// Packing 0 is always lossless and returns standard zero float.
    function testPackZero(int256 exponent) external pure {
        (Float float, bool lossless) = LibDecimalFloat.packLossy(0, exponent);
        assertTrue(lossless, "lossless");
        assertEq(Float.unwrap(float), Float.unwrap(LibDecimalFloat.FLOAT_ZERO), "float");
    }

    /// Error when exponent is too far above int32.max for any non-zero int224
    /// coefficient to lift it back down.
    function testPackExponentOverflow(int256 signedCoefficient, int256 exponent) external {
        exponent = bound(exponent, int256(type(int32).max) + 68, type(int256).max);
        vm.assume(signedCoefficient != 0);
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficient, exponent));
        this.packLossyExternal(signedCoefficient, exponent);
    }

    function packLosslessExternal(int256 signedCoefficient, int256 exponent) external pure returns (Float) {
        return LibDecimalFloat.packLossless(signedCoefficient, exponent);
    }

    /// packLossless reverts LossyConversionToFloat when lossy.
    function testPackLosslessLossyConversionToFloat() external {
        // int224.max + 1 can't fit losslessly — packLossy would normalize it
        // but packLossless must revert.
        int256 signedCoefficient = int256(type(int224).max) + 1;
        int256 exponent = 0;
        vm.expectRevert(abi.encodeWithSelector(LossyConversionToFloat.selector, signedCoefficient, exponent));
        this.packLosslessExternal(signedCoefficient, exponent);
    }

    /// packLossless reverts ExponentOverflow for a value past every Float, at
    /// the first exponent no int224 coefficient can lift and above it, and
    /// LossyConversionToFloat for one that rounds to zero.
    function testPackLosslessErrorByMagnitude() external {
        int256 past = int256(type(int32).max) + 68;
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(1), past));
        this.packLosslessExternal(1, past);
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(-1), type(int256).max));
        this.packLosslessExternal(-1, type(int256).max);
        // One below the ceiling's reach still lifts.
        Float lifted = this.packLosslessExternal(1, past - 1);
        (int256 liftedCoefficient, int256 liftedExponent) = LibDecimalFloat.unpack(lifted);
        assertEq(liftedCoefficient, 1e67, "lifted coefficient");
        assertEq(liftedExponent, int256(type(int32).max), "lifted exponent");

        vm.expectRevert(abi.encodeWithSelector(LossyConversionToFloat.selector, int256(1), type(int256).min));
        this.packLosslessExternal(1, type(int256).min);
        vm.expectRevert(
            abi.encodeWithSelector(LossyConversionToFloat.selector, int256(-9), int256(type(int32).min) - 1)
        );
        this.packLosslessExternal(-9, int256(type(int32).min) - 1);
    }

    function checkPackLossy(
        int256 signedCoefficient,
        int256 exponent,
        int256 expectedCoefficient,
        int256 expectedExponent,
        bool expectedLossless
    ) internal view {
        (Float float, bool lossless) = this.packLossyExternal(signedCoefficient, exponent);
        (int256 unpackedCoefficient, int256 unpackedExponent) = LibDecimalFloat.unpack(float);
        assertEq(unpackedCoefficient, expectedCoefficient, "coefficient");
        assertEq(unpackedExponent, expectedExponent, "exponent");
        assertEq(lossless, expectedLossless, "lossless");
    }

    /// A coefficient just past int224 packs as the int224 bound one exponent
    /// below the digits it fits at, when that is nearer than shedding one
    /// more digit: the nearest Float not exceeding the value (#326, #332).
    function testPackLossyNearestBound() external view {
        int256 two223 = int256(1) << 223;
        int256 max = type(int224).max;
        int256 min = type(int224).min;
        checkPackLossy(two223, 0, max, 0, false);
        checkPackLossy(two223 + 1, 0, max, 0, false);
        checkPackLossy(two223 + 2, 0, (two223 + 2) / 10, 1, true);
        checkPackLossy(two223 * 10 + 9, -5, max, -4, false);
        checkPackLossy(two223 * 1e9, 0, max, 9, false);
        checkPackLossy(-two223 - 1, 0, min, 0, false);
        checkPackLossy(-two223 - 2, 0, (-two223 - 2) / 10, 1, true);
        checkPackLossy(-(two223 + 1) * 1e9, 0, min, 9, false);
        checkPackLossy(two223, type(int32).max, max, type(int32).max, false);
        checkPackLossy(-two223 - 1, type(int32).min, min, type(int32).min, false);
        // The bound's exponent is below the floor, so shedding to it stands.
        checkPackLossy(two223, int256(type(int32).min) - 1, two223 / 10, type(int32).min, false);
    }

    /// Past the ceiling the bound one exponent down is still past it.
    function testPackLossyNearestBoundPastCeiling() external {
        int256 signedCoefficient = int256(type(int224).max) + 3;
        int256 exponent = type(int32).max;
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficient, exponent));
        this.packLossyExternal(signedCoefficient, exponent);
    }

    /// The overflow rule pow and pow10 check before packing: near int32.max,
    /// packLossy reverts exactly when the value is at least
    /// (int224.max / 10 + 1) 10^(int32.max + 1), which is
    /// (2^223 + 2) 10^int32.max, in magnitude (#452).
    /// `isPastEveryFloat` is that rule, so it is checked at every point too
    /// (#649).
    function checkPackLossyOverflowThreshold(int256 signedCoefficient, int256 exponent) internal view {
        bool over = LibExactFloat.overflows(LibExactFloat.u512(LibExactFloat.abs(signedCoefficient)), exponent);
        bool reverted;
        try this.packLossyExternal(signedCoefficient, exponent) {}
        catch (bytes memory err) {
            assertEq(err, abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficient, exponent), "error");
            reverted = true;
        }
        assertEq(reverted, over, "reverted");
        assertEq(
            LibDecimalFloat.isPastEveryFloat(LibExactFloat.abs(signedCoefficient), exponent), over, "isPastEveryFloat"
        );
    }

    function testPackLossyOverflowThreshold(int256 signedCoefficient, int256 exponent) external view {
        exponent = bound(exponent, int256(type(int32).max) - 10, int256(type(int32).max) + 69);
        checkPackLossyOverflowThreshold(signedCoefficient, exponent);
    }

    function testPackLossyOverflowThresholdEdges() external view {
        int256 overCoefficient = type(int224).max / 10 + 1;
        int256 overExponent = int256(type(int32).max) + 1;
        for (uint256 k = 0; k <= 10; k++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 scale = int256(10 ** k);
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 exponent = overExponent - int256(k);
            int256 edge = overCoefficient * scale;
            checkPackLossyOverflowThreshold(edge, exponent);
            checkPackLossyOverflowThreshold(edge - 1, exponent);
            checkPackLossyOverflowThreshold(-edge, exponent);
            checkPackLossyOverflowThreshold(-edge + 1, exponent);
        }
        for (uint256 k = 1; k <= 67; k++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 lift = type(int224).max / int256(10 ** k);
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 exponent = int256(type(int32).max) + int256(k);
            checkPackLossyOverflowThreshold(lift, exponent);
            checkPackLossyOverflowThreshold(lift + 1, exponent);
            checkPackLossyOverflowThreshold(-lift, exponent);
            checkPackLossyOverflowThreshold(-lift - 1, exponent);
        }
    }

    /// `isPastEveryFloat` is where `packLossy` reverts `ExponentOverflow`, by
    /// packLossy's own behaviour rather than an oracle, at every exponent
    /// from which packLossy can shed or lift to the ceiling (#649).
    function testIsPastEveryFloatIsPackLossyOverflow(int256 signedCoefficient, int256 exponent) external view {
        exponent = bound(exponent, int256(type(int32).max) - 90, int256(type(int32).max) + 90);
        bool past = LibDecimalFloat.isPastEveryFloat(LibExactFloat.abs(signedCoefficient), exponent);
        try this.packLossyExternal(signedCoefficient, exponent) {
            assertFalse(past, "packs but past");
        } catch (bytes memory err) {
            assertEq(err, abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficient, exponent), "error");
            assertTrue(past, "overflows but not past");
        }
    }

    function checkIsPastEveryFloatExact(uint256 magnitude, int256 exponent) internal pure {
        assertEq(
            LibDecimalFloat.isPastEveryFloat(magnitude, exponent),
            LibExactFloat.overflows(LibExactFloat.u512(magnitude), exponent),
            "isPastEveryFloat"
        );
    }

    /// `isPastEveryFloat` is the exact threshold for every uint256 magnitude,
    /// including those past int256 that only the parse callers pass, and
    /// every exponent.
    function testIsPastEveryFloatExact(uint256 magnitude, int256 exponent) external pure {
        checkIsPastEveryFloatExact(magnitude, exponent);
    }

    function testIsPastEveryFloatExactNearCeiling(uint256 magnitude, int256 exponent) external pure {
        exponent = bound(exponent, int256(type(int32).max) - 90, int256(type(int32).max) + 90);
        checkIsPastEveryFloatExact(magnitude, exponent);
    }

    /// Either side of the threshold at every exponent where a uint256
    /// magnitude can straddle it, zero at every such exponent, and the
    /// extreme exponents.
    function testIsPastEveryFloatExactEdges() external pure {
        uint256 threshold = 2 ** 223 + 2;
        int256 ceiling = type(int32).max;
        for (uint256 k = 0; k <= 70; k++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 exponent = ceiling + int256(k);
            uint256 below = (threshold - 1) / 10 ** k;
            checkIsPastEveryFloatExact(below, exponent);
            checkIsPastEveryFloatExact(below + 1, exponent);
            checkIsPastEveryFloatExact(0, exponent);
            checkIsPastEveryFloatExact(1, exponent);
            checkIsPastEveryFloatExact(type(uint256).max, exponent);
        }
        for (uint256 k = 1; k <= 11; k++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 exponent = ceiling - int256(k);
            // 10^10 times the threshold is past uint256.
            if (k < 10) {
                uint256 at = threshold * 10 ** k;
                checkIsPastEveryFloatExact(at - 1, exponent);
                checkIsPastEveryFloatExact(at, exponent);
            }
            checkIsPastEveryFloatExact(0, exponent);
            checkIsPastEveryFloatExact(type(uint256).max, exponent);
        }
        // NEVER_PAST_EXPONENT is tight: nothing is past at it, the largest
        // magnitude is one exponent up.
        assertFalse(
            LibDecimalFloat.isPastEveryFloat(type(uint256).max, LibDecimalFloat.NEVER_PAST_EXPONENT), "never past"
        );
        assertTrue(
            LibDecimalFloat.isPastEveryFloat(type(uint256).max, LibDecimalFloat.NEVER_PAST_EXPONENT + 1), "tight"
        );
        int256[4] memory extremes = [type(int256).max, type(int256).min, int256(0), ceiling - 400];
        for (uint256 i = 0; i < extremes.length; i++) {
            checkIsPastEveryFloatExact(0, extremes[i]);
            checkIsPastEveryFloatExact(1, extremes[i]);
            checkIsPastEveryFloatExact(type(uint256).max, extremes[i]);
        }
    }

    /// packLossless(x, 0) is a bitwise identity for non-negative integers
    /// that fit in int224. The packed representation places the coefficient
    /// in the low 224 bits and the exponent (0) in the high 32 bits,
    /// producing the same bytes32 as the raw integer.
    function testPackLosslessZeroExponentIdentity(uint256 value) external pure {
        // Bound to non-negative values that fit in int224.
        value = bound(value, 0, uint256(uint224(type(int224).max)));
        // value fits in int224 so this cast is safe.
        //forge-lint: disable-next-line(unsafe-typecast)
        Float float = LibDecimalFloat.packLossless(int256(value), 0);
        assertEq(Float.unwrap(float), bytes32(value), "packLossless(x, 0) must be bitwise identity");
    }

    /// Lossy zero when exponent is negative below type(int32).min except for zero.
    function testPackNegativeExponentLossyZero(int256 signedCoefficient, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, 1, type(int256).max);
        exponent = bound(exponent, int256(type(int32).min) - 77, int256(type(int32).min) - 77);
        (Float float, bool lossless) = LibDecimalFloat.packLossy(signedCoefficient, exponent);
        assertFalse(lossless, "lossless");
        assertEq(Float.unwrap(float), Float.unwrap(LibDecimalFloat.FLOAT_ZERO), "float");
    }

    /// A coefficient that does not fit in int224 is normalised by dividing by
    /// powers of ten, which raises the exponent. For exponents in the narrow
    /// window just below int32.min this rescaling can lift the final exponent
    /// back to exactly int32.min, so the pack is lossy (the coefficient was
    /// truncated) but the float is non-zero rather than the underflow zero.
    /// `int224.max + 1` raises the exponent by exactly one, so an input
    /// exponent of int32.min - 1 lands the final exponent at int32.min.
    function testPackNegativeExponentLossyNonZeroWindow() external pure {
        int256 signedCoefficient = int256(type(int224).max) + 1;
        int256 exponent = int256(type(int32).min) - 1;
        (Float float, bool lossless) = LibDecimalFloat.packLossy(signedCoefficient, exponent);
        assertFalse(lossless, "lossless");
        assertTrue(Float.unwrap(float) != Float.unwrap(LibDecimalFloat.FLOAT_ZERO), "non-zero");

        // The rescaled coefficient is truncated by one decimal digit and the
        // exponent is lifted by one to exactly the int32 floor.
        (int256 unpackedCoefficient, int256 unpackedExponent) = LibDecimalFloat.unpack(float);
        assertEq(unpackedExponent, int256(type(int32).min), "exponent");
        assertEq(unpackedCoefficient, signedCoefficient / 10, "coefficient");
    }

    /// One step further below int32.min, fitting the coefficient into int224
    /// lifts the exponent by one, which is one short of the floor. The packing
    /// keeps going: it sheds one more digit to reach the floor rather than
    /// giving up on a value that still has 66 digits of magnitude to offer.
    /// Lossy (the shed digits were not zeros), non-zero, at the floor.
    function testPackNegativeExponentLossyNonZeroTwoBelowFloor() external pure {
        int256 signedCoefficient = int256(type(int224).max) + 1;
        int256 exponent = int256(type(int32).min) - 2;
        (Float float, bool lossless) = LibDecimalFloat.packLossy(signedCoefficient, exponent);
        assertFalse(lossless, "lossless");
        assertTrue(Float.unwrap(float) != Float.unwrap(LibDecimalFloat.FLOAT_ZERO), "non-zero");

        (int256 unpackedCoefficient, int256 unpackedExponent) = LibDecimalFloat.unpack(float);
        assertEq(unpackedExponent, int256(type(int32).min), "exponent");
        assertEq(unpackedCoefficient, signedCoefficient / 100, "coefficient");
    }

    /// packLossless accepts a coefficient beyond int224 when the digits it
    /// sheds are all zeros, because the packed value is numerically equal to
    /// the input. The flag reports value preservation, not whether the input
    /// already fitted.
    function testPackLosslessAcceptsExactMultipleBeyondInt224() external pure {
        // int224.max is ~1.35e67, so 1e70 needs exactly three divisions.
        Float float = LibDecimalFloat.packLossless(1e70, 0);
        (int256 unpackedCoefficient, int256 unpackedExponent) = LibDecimalFloat.unpack(float);
        assertEq(unpackedCoefficient, 1e67, "coefficient");
        assertEq(unpackedExponent, 3, "exponent");
    }

    /// packLossless accepts a value below the floor when shedding trailing
    /// zeros is enough to reach it, and reverts when a significant digit would
    /// have to go. The revert carries the ORIGINAL inputs.
    function testPackLosslessBelowFloor() external {
        Float float = LibDecimalFloat.packLossless(70, int256(type(int32).min) - 1);
        (int256 unpackedCoefficient, int256 unpackedExponent) = LibDecimalFloat.unpack(float);
        assertEq(unpackedCoefficient, 7, "coefficient");
        assertEq(unpackedExponent, int256(type(int32).min), "exponent");

        vm.expectRevert(abi.encodeWithSelector(LossyConversionToFloat.selector, int256(7), int256(type(int32).min) - 1));
        this.packLosslessExternal(7, int256(type(int32).min) - 1);
    }

    /// #452: `packLossy` overflows from `(2^223 + 2) × 10^int32.max` in
    /// magnitude for both signs. Below it a value past the largest Float of
    /// its sign truncates into it, so the band is up to three units of
    /// `10^int32.max` past `(2^223 - 1) × 10^int32.max` for a positive value
    /// and up to two past `-2^223 × 10^int32.max` for a negative one. Each
    /// value is written at `int32.max - k` with `k` trailing digits.
    function testPackLossyCeilingTruncationBand() external {
        int256 two223 = int256(1) << 223;
        int256 max = type(int224).max;
        int256 min = type(int224).min;
        int256 m = type(int32).max;
        for (uint256 k = 0; k <= 9; k++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 scale = int256(10 ** k);
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 e = m - int256(k);
            // The last value below the threshold, and the threshold.
            int256 below = (two223 + 2) * scale - 1;
            int256 at = (two223 + 2) * scale;
            checkPackLossy(below, e, max, m, false);
            checkPackLossy(-below, e, min, m, false);
            vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, at, e));
            this.packLossyExternal(at, e);
            vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, -at, e));
            this.packLossyExternal(-at, e);
            // The largest Floats themselves, exact.
            checkPackLossy(max * scale, e, max, m, true);
            checkPackLossy(min * scale, e, min, m, true);
            // Just past them, lossy.
            checkPackLossy(max * scale + 1, e, max, m, false);
            checkPackLossy(min * scale - 1, e, min, m, false);
        }
    }

    /// #450: packLossless reverts ExponentOverflow with the inputs for the
    /// inputs #450 lists, and for the band `packLossy` truncates into the
    /// largest Float of a sign; the largest Floats themselves pack.
    function testPackLosslessPastLargestFloat() external {
        int256 two223 = int256(1) << 223;
        int256 m = type(int32).max;
        int256[2][10] memory past = [
            [two223, m],
            [two223 + 1, m],
            [-two223 - 1, m],
            [two223 * 10, m - 1],
            [two223 + 2, m],
            [-two223 - 2, m],
            [(two223 - 1) * 10 + 1, m - 1],
            [-two223 * 10 - 1, m - 1],
            [(two223 + 2) * 1e9 - 1, m - 9],
            [-(two223 + 2) * 1e9 + 1, m - 9]
        ];
        for (uint256 i = 0; i < past.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, past[i][0], past[i][1]));
            this.packLosslessExternal(past[i][0], past[i][1]);
        }
        checkPackLosslessExact(two223 - 1, m, two223 - 1, m);
        checkPackLosslessExact(-two223, m, -two223, m);
        checkPackLosslessExact((two223 - 1) * 10, m - 1, two223 - 1, m);
        checkPackLosslessExact(-two223 * 1e9, m - 9, -two223, m);
    }

    function checkPackLosslessExact(int256 c, int256 e, int256 expectedC, int256 expectedE) internal view {
        (int256 actualC, int256 actualE) = LibDecimalFloat.unpack(this.packLosslessExternal(c, e));
        assertEq(actualC, expectedC, "coefficient");
        assertEq(actualE, expectedE, "exponent");
    }

    /// packLossless against exact maths: past the largest Float of its sign
    /// is `ExponentOverflow`; otherwise the value packs iff it is a Float,
    /// that is with its trailing zeros stripped its coefficient is within the
    /// sign's int224 bound and its exponent at or above int32.min. Either
    /// error reports the inputs.
    function checkPackLosslessAgainstExact(int256 c, int256 e) internal view {
        bool negative = c < 0;
        uint256 magnitude = LibExactFloat.abs(c);
        uint256 limit = LibExactFloat.coefficientLimit(negative);
        bool past =
            LibExactFloat.cmpScaled(LibExactFloat.u512(magnitude), e, LibExactFloat.u512(limit), type(int32).max) > 0;
        bool isFloat = true;
        if (magnitude != 0) {
            int256 stripped = e;
            while (magnitude % 10 == 0) {
                magnitude /= 10;
                stripped++;
            }
            isFloat = magnitude <= limit && stripped >= type(int32).min;
        }
        try this.packLosslessExternal(c, e) returns (Float float) {
            assertFalse(past, "past packed");
            assertTrue(isFloat, "not a Float packed");
            (int256 actualC, int256 actualE) = LibDecimalFloat.unpack(float);
            assertTrue(LibExactFloat.eq(actualC, actualE, c, e), "value");
        } catch (bytes memory err) {
            bytes4 expected = past ? ExponentOverflow.selector : isFloat ? bytes4(0) : LossyConversionToFloat.selector;
            assertEq(err, abi.encodeWithSelector(expected, c, e), "error");
        }
    }

    function testPackLosslessAgainstExact(int256 c, int256 e) external view {
        e = bound(e, int256(type(int32).min) - 80, int256(type(int32).max) + 80);
        checkPackLosslessAgainstExact(c, e);
    }

    /// The same, around the largest Floats: `±2^223 × 10^k + delta` at
    /// `int32.max - k`.
    function testPackLosslessAgainstExactCeiling(uint256 k, int256 delta, bool negative) external view {
        k = bound(k, 0, 9);
        delta = bound(delta, -1e12, 1e12);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 c = (int256(1) << 223) * int256(10 ** k) + delta;
        // forge-lint: disable-next-line(unsafe-typecast)
        checkPackLosslessAgainstExact(negative ? -c : c, int256(type(int32).max) - int256(k));
    }
}
