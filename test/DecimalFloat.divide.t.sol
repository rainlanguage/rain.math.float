// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat} from "src/DecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract DecimalFloatDivideTest is Test {
    // /// 1 / 3
    // function testDivide1Over3() external pure {
    //     DecimalFloat a = LibDecimalFloat.fromParts(1, 0);
    //     DecimalFloat b = LibDecimalFloat.fromParts(3, 0);
    //     DecimalFloat actual = a.divide(b);
    //     (int256 signedCoefficient, int256 exponent) = actual.toParts();
    //     assertEq(signedCoefficient, 33333333333333333333333333333333333333, "coefficient");
    //     assertEq(exponent, -38, "exponent");
    // }

    // /// - 1 / 3
    // function testDivideNegative1Over3() external pure {
    //     DecimalFloat a = LibDecimalFloat.fromParts(-1, 0);
    //     DecimalFloat b = LibDecimalFloat.fromParts(3, 0);
    //     DecimalFloat actual = a.divide(b);
    //     (int256 signedCoefficient, int256 exponent) = actual.toParts();
    //     assertEq(signedCoefficient, -33333333333333333333333333333333333333, "coefficient");
    //     assertEq(exponent, -38, "exponent");
    // }

    // /// 1 / 3 gas
    // function testDivide1Over3Gas() external pure {
    //     DecimalFloat.wrap(1).divide(DecimalFloat.wrap(3));
    // }

    /// 1 / 3 gas by parts
    function testDivide1Over3Gas01() external pure {
        LibDecimalFloat.divide(1e37, -37, 3e37, -37);
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

    // /// 1e18 / 3
    // function testDivide1e18Over3() external pure {
    //     DecimalFloat.wrap(1e18).divide(DecimalFloat.wrap(3));
    // }

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
        assertEq(signedCoefficientA, 11111111111111111111111111111111111111);
        assertEq(exponentA, -38);

        // 1 / 3
        (int256 signedCoefficientB, int256 exponentB) = LibDecimalFloat.divide(1, 0, 3, 0);
        assertEq(signedCoefficientB, 33333333333333333333333333333333333333);
        assertEq(exponentB, -38);

        // (1 / 9) / (1 / 3)
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloat.divide(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(signedCoefficient, 33333333333333333333333333333333333333);
        assertEq(exponent, -38);
    }
}
