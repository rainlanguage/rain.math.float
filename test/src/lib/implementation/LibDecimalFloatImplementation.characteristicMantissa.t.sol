// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";

import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

contract LibDecimalFloatImplementationCharacteristicMantissaTest is Test {
    function checkCharacteristicMantissa(
        int256 signedCoefficient,
        int256 exponent,
        int256 expectedCharacteristic,
        int256 expectedMantissa
    ) internal pure {
        (int256 actualCharacteristic, int256 actualMantissa) =
            LibDecimalFloatImplementation.characteristicMantissa(signedCoefficient, exponent);

        assertEq(actualCharacteristic, expectedCharacteristic, "Characteristic mismatch");
        assertEq(actualMantissa, expectedMantissa, "Mantissa mismatch");
    }

    function testCharacteristicMantissaExamples() public pure {
        checkCharacteristicMantissa(0, 0, 0, 0);
        checkCharacteristicMantissa(0, 1, 0, 0);

        checkCharacteristicMantissa(5.4304950862250382e16, -16, 5e16, 4304950862250382);
        checkCharacteristicMantissa(-5.4304950862250382e16, -16, -5e16, -0.4304950862250382e16);

        checkCharacteristicMantissa(5.4304950862250382e16, -76, 0, 5.4304950862250382e16);
        checkCharacteristicMantissa(-5.4304950862250382e16, -76, 0, -5.4304950862250382e16);

        // Exact multiple => zero mantissa
        checkCharacteristicMantissa(5e16, -16, 5e16, 0);
        checkCharacteristicMantissa(-5e16, -16, -5e16, 0);
        // Off-by-one around the multiple
        checkCharacteristicMantissa(5e16 + 1, -16, 5e16, 1);
        checkCharacteristicMantissa(-5e16 - 1, -16, -5e16, -1);

        // Boundary at exponent -76 (scale = 1e76)
        checkCharacteristicMantissa(1e76, -76, 1e76, 0);
        checkCharacteristicMantissa(1e76 + 1, -76, 1e76, 1);
        checkCharacteristicMantissa(-1e76, -76, -1e76, 0);
        checkCharacteristicMantissa(-1e76 - 1, -76, -1e76, -1);

        // Beyond boundary at exponent -77 (scale > int256.max): characteristic must be 0
        checkCharacteristicMantissa(1, -77, 0, 1);
        checkCharacteristicMantissa(-1, -77, 0, -1);
    }

    function testCharacteristicMantissaNonNegExponent(int256 signedCoefficient, int256 exponent) public pure {
        exponent = bound(exponent, 0, type(int256).max);
        checkCharacteristicMantissa(signedCoefficient, exponent, signedCoefficient, 0);
    }

    function testCharacteristicMantissaNegExponentLarge(int256 signedCoefficient, int256 exponent) public pure {
        exponent = bound(exponent, type(int256).min, -77);
        checkCharacteristicMantissa(signedCoefficient, exponent, 0, signedCoefficient);
    }

    function testCharacteristicMantissaNegExponentSmall(int256 signedCoefficient) public pure {
        for (int256 exponent = 1; exponent <= 76; exponent++) {
            // exponent [1, 76]
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 scale = int256(10 ** uint256(exponent));

            int256 expectedMantissa = signedCoefficient % scale;
            int256 expectedCharacteristic = signedCoefficient / scale * scale;

            checkCharacteristicMantissa(signedCoefficient, -exponent, expectedCharacteristic, expectedMantissa);
        }
    }
}
