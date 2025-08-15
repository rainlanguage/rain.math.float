// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {
    LibDecimalFloatImplementation,
    EXPONENT_MIN,
    EXPONENT_MAX
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {THREES, ONES} from "../../../lib/LibCommonResults.sol";

contract LibDecimalFloatImplementationDivTest is Test {
    function checkDiv(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB,
        int256 signedCoefficientC,
        int256 exponentC
    ) internal pure {
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.div(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(signedCoefficient, signedCoefficientC, "coefficient");
        assertEq(exponent, exponentC, "exponent");
    }

    /// 1 / 3 gas by parts 10
    function testDiv1Over3Gas10() external pure {
        (int256 c, int256 e) = LibDecimalFloatImplementation.div(1, 0, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.div(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.div(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.div(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.div(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.div(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.div(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.div(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.div(c, e, 3e37, -37);
        (c, e) = LibDecimalFloatImplementation.div(c, e, 3e37, -37);
    }

    /// 1 / 3
    function testDiv1Over3() external pure {
        checkDiv(1, 0, 3, 0, THREES, -39);
    }

    /// - 1 / 3
    function testDivNegative1Over3() external pure {
        checkDiv(-1, 0, 3, 0, -THREES, -39);
    }

    /// 1 / 3 gas
    function testDiv1Over3Gas0() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.div(1e37, -37, 3e37, -37);
        (signedCoefficient, exponent);
    }

    /// 1e18 / 3
    function testDiv1e18Over3() external pure {
        checkDiv(1e18, 0, 3, 0, THREES, -21);
    }

    /// 10,0 / 1e38,-37 == 1
    function testDivTenOverOOMs() external pure {
        checkDiv(10, 0, 1e38, -37, 1e39, -39);
    }

    /// 1e38,-37 / 2,0 == 5
    function testDivOOMsOverTen() external pure {
        checkDiv(1e38, -37, 2, 0, 5e38, -38);
    }

    /// 5e37,-37 / 2e37,-37 == 2.5
    function testDivOOMs5and2() external pure {
        checkDiv(5e37, -37, 2e37, -37, 25e38, -39);
    }

    /// (1 / 9) / (1 / 3) == 0.333..
    function testDiv1Over9Over1Over3() external pure {
        // 1 / 9
        (int256 signedCoefficientA, int256 exponentA) = LibDecimalFloatImplementation.div(1, 0, 9, 0);
        assertEq(signedCoefficientA, ONES);
        assertEq(exponentA, -39);

        // 1 / 3
        (int256 signedCoefficientB, int256 exponentB) = LibDecimalFloatImplementation.div(1, 0, 3, 0);
        assertEq(signedCoefficientB, THREES);
        assertEq(exponentB, -39);

        // (1 / 9) / (1 / 3)
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.div(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(signedCoefficient, 333333333333333333333333333333333333336);
        assertEq(exponent, -39);
    }

    /// forge-config: default.fuzz.runs = 100
    function testUnnormalizedThreesDiv0(int256 exponentA, int256 exponentB) external pure {
        exponentA = bound(exponentA, EXPONENT_MIN / 2, EXPONENT_MAX / 2);
        exponentB = bound(exponentB, EXPONENT_MIN / 2, EXPONENT_MAX / 2);

        int256 d = 3;
        int256 di = 0;
        while (true) {
            int256 i = 1;
            int256 j = -39 - di;
            while (true) {
                // want to see full precision on the THREES regardless of the
                // scale of the numerator and denominator.
                checkDiv(i, exponentA, d, exponentB, THREES, exponentA - exponentB + j);

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
