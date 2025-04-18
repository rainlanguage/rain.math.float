// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {
    LibDecimalFloatImplementation,
    EXPONENT_MIN,
    EXPONENT_MAX
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {THREES, ONES} from "../../../lib/LibCommonResults.sol";

contract LibDecimalFloatImplementationDivideTest is Test {
    function checkDivision(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB,
        int256 signedCoefficientC,
        int256 exponentC
    ) internal pure {
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.divide(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(signedCoefficient, signedCoefficientC, "coefficient");
        assertEq(exponent, exponentC, "exponent");
    }

    /// 1 / 3 gas by parts 10
    function testDivide1Over3Gas10() external pure {
        (int256 c, int256 e) = LibDecimalFloatImplementation.divide(1, 0, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.divide(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.divide(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.divide(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.divide(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.divide(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.divide(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.divide(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.divide(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.divide(c, e, 3e37, -37);
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
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.divide(1e37, -37, 3e37, -37);
        (signedCoefficient, exponent);
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
        (int256 signedCoefficientA, int256 exponentA) = LibDecimalFloatImplementation.divide(1, 0, 9, 0);
        assertEq(signedCoefficientA, ONES);
        assertEq(exponentA, -38);

        // 1 / 3
        (int256 signedCoefficientB, int256 exponentB) = LibDecimalFloatImplementation.divide(1, 0, 3, 0);
        assertEq(signedCoefficientB, THREES);
        assertEq(exponentB, -38);

        // (1 / 9) / (1 / 3)
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.divide(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(signedCoefficient, THREES);
        assertEq(exponent, -38);
    }

    /// forge-config: default.fuzz.runs = 100
    function testUnnormalizedThreesDivision0(int256 exponentA, int256 exponentB) external pure {
        exponentA = bound(exponentA, EXPONENT_MIN / 2, EXPONENT_MAX / 2);
        exponentB = bound(exponentB, EXPONENT_MIN / 2, EXPONENT_MAX / 2);

        int256 d = 3;
        int256 di = 0;
        while (true) {
            int256 i = 1;
            int256 j = -38 - di;
            while (true) {
                // want to see full precision on the THREES regardless of the
                // scale of the numerator and denominator.
                checkDivision(i, exponentA, d, exponentB, THREES, exponentA - exponentB + j);

                if (i == 1e76) {
                    break;
                }

                i *= 10;
                ++j;
            }

            if (d == 3e76) {
                break;
            }
            d *= 10;
            ++di;
        }
    }
}
