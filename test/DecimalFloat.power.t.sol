// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, COMPARE_EQUAL} from "src/DecimalFloat.sol";

import {Test, console} from "forge-std/Test.sol";

contract DecimalFloatPowerTest is Test {
    function checkPower(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal view {
        uint256 a = gasleft();
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloat.power(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        uint256 b = gasleft();
        console.log("%d %d Gas used: %d", uint256(signedCoefficientA), uint256(exponentA), a - b);
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signedCoefficient");
        assertEq(actualExponent, expectedExponent, "exponent");
    }

    function testPowers() external view {
        checkPower(5e37, -38, 3e37, -36, 9.3283582089552238805970149253731343283e37, -47);
        checkPower(5e37, -38, 6e37, -36, 8.7108013937282229965156794425087108013e37, -56);
    }
}
