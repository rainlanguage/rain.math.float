// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, COMPARE_EQUAL} from "src/lib/LibDecimalFloat.sol";

import {Test, console} from "forge-std/Test.sol";

contract LibDecimalFloatLog10Test is Test {
    function checkLog10(
        int256 signedCoefficient,
        int256 exponent,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal view {
        uint256 a = gasleft();
        (int256 actualSignedCoefficient, int256 actualExponent) = LibDecimalFloat.log10(signedCoefficient, exponent);
        uint256 b = gasleft();
        console.log("%d %d Gas used: %d", uint256(signedCoefficient), uint256(exponent), a - b);
        assertEq(actualSignedCoefficient, expectedSignedCoefficient);
        assertEq(actualExponent, expectedExponent);
    }

    function testExactLogs() external view {
        checkLog10(1, 0, 0, 0);
        checkLog10(10, 0, 1, 0);
        checkLog10(100, 0, 2, 0);
        checkLog10(1000, 0, 3, 0);
        checkLog10(10000, 0, 4, 0);
    }

    // function testExactLookups() external view {
    //     checkLog10(1001, 0, 3.0004e37, -37);
    //     checkLog10(1001, -1, 2.0004e37, -37);
    //     checkLog10(1001, -2, 1.0004e37, -37);
    //     checkLog10(1001, -3, 4e37, -41);

    //     checkLog10(1002, -2, 1.0009e37, -37);
    //     checkLog10(1099, -2, 1.0411e37, -37);
    // }

    // function testInterpolatedLookups() external view {
    //     checkLog10(10015, -3, 1.00065e37, -37);
    // }

    // // This can't work until the full lookup table is implemented.
    // function testSub1() external view {
    //     checkLog10(1001, -4, -0.99960039960039960039960039960039960039e38, -38);
    // }
}
