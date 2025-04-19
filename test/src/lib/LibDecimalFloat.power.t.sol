// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LogTest} from "../../abstract/LogTest.sol";

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {console2} from "forge-std/Test.sol";

contract LibDecimalFloatPowerTest is LogTest {
    using LibDecimalFloat for Float;

    function checkPower(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal {
        Float a = LibDecimalFloat.packLossless(signedCoefficientA, exponentA);
        Float b = LibDecimalFloat.packLossless(signedCoefficientB, exponentB);
        address tables = logTables();
        uint256 beforeGas = gasleft();
        Float c = a.power(b, tables);
        uint256 afterGas = gasleft();
        console2.log("%d %d Gas used: %d", uint256(signedCoefficientA), uint256(exponentA), beforeGas - afterGas);
        (int256 actualSignedCoefficient, int256 actualExponent) = c.unpack();
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signedCoefficient");
        assertEq(actualExponent, expectedExponent, "exponent");
    }

    function testPowers() external {
        checkPower(5e37, -38, 3e37, -36, 9.3283582089552238805970149253731343283e37, -47);
        checkPower(5e37, -38, 6e37, -36, 8.7108013937282229965156794425087108013e37, -56);
    }

    function checkRoundTrip(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
    {
        Float a = LibDecimalFloat.packLossless(signedCoefficientA, exponentA);
        Float b = LibDecimalFloat.packLossless(signedCoefficientB, exponentB);
        address tables = logTables();
        Float c = a.power(b, tables);
        Float roundTrip = c.power(b.inv(), tables);
        Float diff = a.divide(roundTrip).sub(LibDecimalFloat.packLossless(1, 0)).abs();

        assertTrue(diff.lt(LibDecimalFloat.packLossless(0.0025e4, -4)), "diff");
    }

    /// X^Y^(1/Y) = X
    /// Can generally round trip whatever within 1% of the original value.
    function testRoundTrip() external {
        checkRoundTrip(5, 0, 2, 0);
        checkRoundTrip(5, 0, 3, 0);
        checkRoundTrip(50, 0, 40, 0);
        checkRoundTrip(5, -1, 3, -1);
        checkRoundTrip(5, -1, 2, -1);
        checkRoundTrip(5, 100, 3, 20);
        checkRoundTrip(5, -1, 100, 0);
    }
}
