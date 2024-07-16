// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {THREES, ONES} from "../lib/LibCommonResults.sol";
import {LibDecimalFloat} from "src/lib/LibDecimalFloat.sol";

import {Test, console2} from "forge-std/Test.sol";

contract LibDecimalFloatDivideTest is Test {
    function checkDivision(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB,
        int256 signedCoefficientC,
        int256 exponentC
    ) internal pure {
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloat.divide(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(signedCoefficient, signedCoefficientC, "coefficient");
        assertEq(exponent, exponentC, "exponent");
    }

    /// 1 / 3
    function testDivide1Over3() external pure {
        checkDivision(1, 0, 3, 0, THREES, -38);
    }

    /// - 1 / 3
    function testDivideNegative1Over3() external pure {
        checkDivision(-1, 0, 3, 0, -THREES, -38);
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
        checkDivision(1e18, 0, 3, 0, THREES, -20);
    }

    /// 10,0 / 1e38,-37 == 1
    function testDivideTenOverOOMs() external pure {
        checkDivision(10, 0, 1e38, -37, 1e38, -38);
    }

    /// 1e38,-37 / 2,0 == 5
    function testDivideOOMsOverTen() external pure {
        checkDivision(1e38, -37, 2, 0, 5e37, -37);
    }

    /// 5e37,-37 / 2e37,-37 == 2.5
    function testDivideOOMs5and2() external pure {
        checkDivision(5e37, -37, 2e37, -37, 25e37, -38);
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

    function testUnnormalizedThreesDivision0() external pure {
        int256 i = 1;
        int256 j = -38;
        while (true) {
            checkDivision(i, 0, 3, 0, THREES, j);

            if (i == 1e76) {
                break;
            }

            i *= 10;
            ++j;
        }
    }
}
