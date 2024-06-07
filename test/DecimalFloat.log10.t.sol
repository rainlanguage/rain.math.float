// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {DecimalFloat, LibDecimalFloat, COMPARE_EQUAL} from "src/DecimalFloat.sol";

import {Test, console} from "forge-std/Test.sol";

contract DecimalFloatLog10Test is Test {
    using LibDecimalFloat for DecimalFloat;

    // /// log10(1) = 0
    // function testLog10One() external view {
    //     uint256 a = gasleft();
    //     (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.log10ByParts(1, 0, 5);
    //     uint256 b = gasleft();
    //     console.log("Gas used: %d", a - b);
    //     assertEq(signedCoefficient, 0);
    //     assertEq(exponent, 0);
    // }

    // /// log10(10) = 1
    // function testLog10Ten() external view {
    //     uint256 a = gasleft();
    //     (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.log10ByParts(10, 0, 5);
    //     uint256 b = gasleft();
    //     console.log("Gas used: %d", a - b);
    //     assertEq(signedCoefficient, 100000000000000000000000000000000000000);
    //     assertEq(exponent, -38);
    // }

    // /// log10(100) = 2
    // function testLog10Hundred() external view {
    //     uint256 a = gasleft();
    //     (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.log10ByParts(100, 0, 5);
    //     uint256 b = gasleft();
    //     console.log("Gas used: %d", a - b);
    //     assertEq(signedCoefficient, 20000000000000000000000000000000000000);
    //     assertEq(exponent, -37);
    // }

    // /// log10(2) = 0.301029
    // function testLog10Two() external view {
    //     uint256 a = gasleft();
    //     (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.log10ByParts(2, 0, 4);
    //     uint256 b = gasleft();
    //     console.log("Gas used: %d", a - b);
    //     assertEq(signedCoefficient, 301020408163265306122448979591836734);
    //     assertEq(exponent, -36);
    // }

    function testLookup() external view {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.log10ByPartsTable(1, 0);
        assertEq(signedCoefficient, 0);
        assertEq(exponent, 0);

        (signedCoefficient, exponent) = LibDecimalFloat.log10ByPartsTable(1, 1);
        assertEq(signedCoefficient, 1);
        assertEq(exponent, 0);

        (signedCoefficient, exponent) = LibDecimalFloat.log10ByPartsTable(1, 2);
        assertEq(signedCoefficient, 2);
        assertEq(exponent, 0);

        (signedCoefficient, exponent) = LibDecimalFloat.log10ByPartsTable(1001, -2);
        assertEq(signedCoefficient, 4e34);
        assertEq(exponent, -38);

        (signedCoefficient, exponent) = LibDecimalFloat.log10ByPartsTable(10015, -3);
        assertEq(signedCoefficient, 6.5e37);
        assertEq(exponent, -41);

        (signedCoefficient, exponent) = LibDecimalFloat.log10ByPartsTable(1002, -2);
        assertEq(signedCoefficient, 9e34);
        assertEq(exponent, -38);

        (signedCoefficient, exponent) = LibDecimalFloat.log10ByPartsTable(1099, -2);
        assertEq(signedCoefficient, 411e34);
        assertEq(exponent, -38);
    }
}
