// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, ExponentOverflow, Float} from "src/lib/LibDecimalFloat.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";
import {LossyConversionToFloat} from "src/error/ErrDecimalFloat.sol";
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
    /// (int224.max / 10 + 1) 10^(int32.max + 1) in magnitude.
    function checkPackLossyOverflowThreshold(int256 signedCoefficient, int256 exponent) internal view {
        bool over = LibTestExactDecimal.overflows(
            LibTestExactDecimal.u512(LibTestExactDecimal.abs(signedCoefficient)), exponent
        );
        bool reverted;
        try this.packLossyExternal(signedCoefficient, exponent) {}
        catch {
            reverted = true;
        }
        assertEq(reverted, over, "reverted");
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
}
