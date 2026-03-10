// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, ExponentOverflow, Float} from "src/lib/LibDecimalFloat.sol";
import {CoefficientOverflow} from "src/error/ErrDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";

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

    /// Error when exponent larger than int32.max except for zero.
    function testPackExponentOverflow(int256 signedCoefficient, int256 exponent) external {
        exponent = bound(exponent, int256(type(int32).max) + 1, type(int256).max - 77);
        vm.assume(signedCoefficient != 0);
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficient, exponent));
        this.packLossyExternal(signedCoefficient, exponent);
    }

    function packLosslessExternal(int256 signedCoefficient, int256 exponent) external pure returns (Float) {
        return LibDecimalFloat.packLossless(signedCoefficient, exponent);
    }

    /// packLossless reverts with CoefficientOverflow when lossy.
    function testPackLosslessCoefficientOverflow() external {
        // int224.max + 1 can't fit losslessly — packLossy would normalize it
        // but packLossless must revert.
        int256 signedCoefficient = int256(type(int224).max) + 1;
        int256 exponent = 0;
        vm.expectRevert(abi.encodeWithSelector(CoefficientOverflow.selector, signedCoefficient, exponent));
        this.packLosslessExternal(signedCoefficient, exponent);
    }

    /// packLossy returns lossless=false but a valid non-zero Float when the
    /// coefficient exceeds int224 but can be normalized by dividing by 10.
    function testPackLossyButPackable() external view {
        // int224.max + 1 doesn't fit in int224, but dividing by 10 does.
        int256 signedCoefficient = int256(type(int224).max) + 1;
        int256 exponent = 0;
        (Float float, bool lossless) = this.packLossyExternal(signedCoefficient, exponent);
        assertFalse(lossless, "lossless");
        assertTrue(Float.unwrap(float) != Float.unwrap(LibDecimalFloat.FLOAT_ZERO), "non-zero");

        // The packed value should unpack to a truncated coefficient with
        // incremented exponent.
        (int256 unpackedCoefficient, int256 unpackedExponent) = LibDecimalFloat.unpack(float);
        assertEq(unpackedExponent, 1, "exponent");
        assertEq(unpackedCoefficient, signedCoefficient / 10, "coefficient");
    }

    /// Lossy zero when exponent is negative below type(int32).min except for zero.
    function testPackNegativeExponentLossyZero(int256 signedCoefficient, int256 exponent) external view {
        exponent = bound(exponent, type(int256).min, int256(type(int32).min) - 77);
        vm.assume(signedCoefficient != 0);
        (Float float, bool lossless) = this.packLossyExternal(signedCoefficient, exponent);
        assertFalse(lossless, "lossless");
        assertEq(Float.unwrap(float), Float.unwrap(LibDecimalFloat.FLOAT_ZERO), "float");
    }
}
