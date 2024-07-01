// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {THREES, ONES} from "../lib/LibCommonResults.sol";
import {LibDecimalFloat} from "src/LibDecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatDivideTest is Test {
    /// 1 / 3
    function testDivide1Over3() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.divide(1, 0, 3, 0);
        assertEq(signedCoefficient, THREES, "coefficient");
        assertEq(exponent, -38, "exponent");
    }

    /// - 1 / 3
    function testDivideNegative1Over3() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.divide(-1, 0, 3, 0);
        assertEq(signedCoefficient, -THREES, "coefficient");
        assertEq(exponent, -38, "exponent");
    }

    /// 1 / 3 gas
    function testDivide1Over3Gas0() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.divide(1e37, -37, 3e37, -37);
        (signedCoefficient, exponent);
    }

    /// 1 / 3 gas by parts 10
    function testDivide1Over3Gas10() external pure {
        (int256 c, int256 e) = LibDecimalFloat.divide(1, 0, 3e37, -37);
        (c, e) = LibDecimalFloat.divide(c, e, 3e37, -37);
        (c, e) = LibDecimalFloat.divide(c, e, 3e37, -37);
        (c, e) = LibDecimalFloat.divide(c, e, 3e37, -37);
        (c, e) = LibDecimalFloat.divide(c, e, 3e37, -37);
        (c, e) = LibDecimalFloat.divide(c, e, 3e37, -37);
        (c, e) = LibDecimalFloat.divide(c, e, 3e37, -37);
        (c, e) = LibDecimalFloat.divide(c, e, 3e37, -37);
        (c, e) = LibDecimalFloat.divide(c, e, 3e37, -37);
        (c, e) = LibDecimalFloat.divide(c, e, 3e37, -37);
    }

    /// 1e18 / 3
    function testDivide1e18Over3() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.divide(1e18, 0, 3, 0);
        assertEq(signedCoefficient, THREES);
        assertEq(exponent, -20);
    }

    /// 10,0 / 1e38,-37 == 1
    function testDivideTenOverOOMs() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.divide(10, 0, 1e38, -37);
        assertEq(signedCoefficient, 1e37);
        assertEq(exponent, -37);
    }

    /// 1e38,-37 / 2,0 == 5
    function testDivideOOMsOverTen() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.divide(1e38, -37, 2, 0);
        assertEq(signedCoefficient, 5e37);
        assertEq(exponent, -37);
    }

    /// 5e37,-37 / 2e37,-37 == 2.5
    function testDivideOOMs5and2() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.divide(5e37, -37, 2e37, -37);
        assertEq(signedCoefficient, 25e36);
        assertEq(exponent, -37);
    }

    /// (1 / 9) / (1 / 3) == 0.333..
    function testDivide1Over9Over1Over3() external pure {
        // 1 / 9
        (int256 signedCoefficientA, int256 exponentA) = LibDecimalFloat.divide(1, 0, 9, 0);
        assertEq(signedCoefficientA, ONES);
        assertEq(exponentA, -38);

        // 1 / 3
        (int256 signedCoefficientB, int256 exponentB) = LibDecimalFloat.divide(1, 0, 3, 0);
        assertEq(signedCoefficientB, THREES);
        assertEq(exponentB, -38);

        // (1 / 9) / (1 / 3)
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloat.divide(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(signedCoefficient, THREES);
        assertEq(exponent, -38);
    }
}
