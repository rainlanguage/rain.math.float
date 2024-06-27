// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, COMPARE_EQUAL} from "src/DecimalFloat.sol";

import {Test, console} from "forge-std/Test.sol";

contract DecimalFloatPower10Test is Test {
    function checkPower10(
        int256 signedCoefficient,
        int256 exponent,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal view {
        uint256 a = gasleft();
        (int256 actualSignedCoefficient, int256 actualExponent) = LibDecimalFloat.power10(signedCoefficient, exponent);
        uint256 b = gasleft();
        console.log("%d %d Gas used: %d", uint256(signedCoefficient), uint256(exponent), a - b);
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signedCoefficient");
        assertEq(actualExponent, expectedExponent, "exponent");
    }

    function testExactPowers() external view {
        // 10^1 = 10
        checkPower10(1, 0, 1e37, -36);
        // 10^10 = 10000000000
        // checkPower10(1, 1, 10, 0);
        // checkPower10(1, 2, 100, 0);
        // checkPower10(1, 3, 1000, 0);
        // checkPower10(1, 4, 10000, 0);
    }

    function testExactLookups() external view {
        // 10^2 = 100
        checkPower10(2, 0, 1e37, -35);
        // 10^3 = 1000
        checkPower10(3, 0, 1e37, -34);
        // 10^4 = 10000
        checkPower10(4, 0, 1e37, -33);
        // 10^5 = 100000
        checkPower10(5, 0, 1e37, -32);
        // 10^6 = 1000000
        checkPower10(6, 0, 1e37, -31);
        // 10^7 = 10000000
        checkPower10(7, 0, 1e37, -30);
        // 10^8 = 100000000
        checkPower10(8, 0, 1e37, -29);
        // 10^9 = 1000000000
        checkPower10(9, 0, 1e37, -28);

        // 10^1.5 = 31.622776601683793319988935444327074859
        checkPower10(1.5e37, -37, 3.162e37, -36);
    }

    function testInterpolatedLookups() external view {
        // 10^1.55555 = 35.9376769153
        checkPower10(1.55555e37, -37, 3.593005e37, -36);
    }

    // function testSub1() external view {
    //     checkPower10(1, -4, 1, -4);
    // }
}

// 359400000000000000000000000000000000000