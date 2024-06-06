// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {DecimalFloat, LibDecimalFloat, COMPARE_EQUAL} from "src/DecimalFloat.sol";

import {Test, console} from "forge-std/Test.sol";

contract DecimalFloatLog10Test is Test {
    using LibDecimalFloat for DecimalFloat;

    /// log10(1) = 0
    function testLog10One() external view {
        uint256 a = gasleft();
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.log10ByParts(1, 0, 5);
        uint256 b = gasleft();
        console.log("Gas used: %d", a - b);
        assertEq(signedCoefficient, 0);
        assertEq(exponent, 0);
    }

    /// log10(10) = 1
    function testLog10Ten() external view {
        uint256 a = gasleft();
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.log10ByParts(10, 0, 5);
        uint256 b = gasleft();
        console.log("Gas used: %d", a - b);
        assertEq(signedCoefficient, 100000000000000000000000000000000000000);
        assertEq(exponent, -38);
    }

    /// log10(100) = 2
    function testLog10Hundred() external view {
        uint256 a = gasleft();
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.log10ByParts(100, 0, 5);
        uint256 b = gasleft();
        console.log("Gas used: %d", a - b);
        assertEq(signedCoefficient, 20000000000000000000000000000000000000);
        assertEq(exponent, -37);
    }

    /// log10(2) = 0.301029
    function testLog10Two() external view {
        uint256 a = gasleft();
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.log10ByParts(2, 0, 4);
        uint256 b = gasleft();
        console.log("Gas used: %d", a - b);
        assertEq(signedCoefficient, 301020408163265306122448979591836734);
        assertEq(exponent, -36);
    }
}
