// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LogTest} from "../../abstract/LogTest.sol";

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {PowNegativeBase} from "src/error/ErrDecimalFloat.sol";
import {console2} from "forge-std/Test.sol";

contract LibDecimalFloatSqrtTest is LogTest {
    using LibDecimalFloat for Float;

    function diffLimit() internal pure returns (Float) {
        return LibDecimalFloat.packLossless(19, -4);
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
        checkSqrt(2, 0, 1415, -3);
        checkSqrt(4, 0, 2e3, -3);
        checkSqrt(16, 0, 3999500000000000000000000000000000000000000000000000000000000000000, -66);
    }

    function testSqrtNegative(Float a) external {
        // We can't simply minus 0 to get a negative base.
        vm.assume(!a.isZero());

        if (a.gt(LibDecimalFloat.FLOAT_ZERO)) {
            a = a.minus();
        }

        address tables = logTables();

        (int256 signedCoefficient, int256 exponent) = a.unpack();
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
}
