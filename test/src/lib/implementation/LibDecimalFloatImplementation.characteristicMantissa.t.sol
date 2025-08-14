// SPDX-License-Identifier: CAL
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
    }
}
