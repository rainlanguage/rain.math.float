// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {THREES, ONES} from "../../lib/LibCommonResults.sol";
import {LibDecimalFloat, EXPONENT_MIN, EXPONENT_MAX, Float} from "src/lib/LibDecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatDivideTest is Test {
    using LibDecimalFloat for Float;

    function divideExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (int256, int256)
    {
        return LibDecimalFloat.divide(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    function divideExternal(Float memory floatA, Float memory floatB) external pure returns (Float memory) {
        return LibDecimalFloat.divide(floatA, floatB);
    }
    /// Stack and mem are the same.

    function testDivideMem(Float memory a, Float memory b) external {
        try this.divideExternal(a.signedCoefficient, a.exponent, b.signedCoefficient, b.exponent) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            Float memory float = this.divideExternal(a, b);
            assertEq(signedCoefficient, float.signedCoefficient);
            assertEq(exponent, float.exponent);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.divideExternal(a, b);
        }
    }

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

    /// forge-config: default.fuzz.runs = 100
    function testUnnormalizedThreesDivision0(int256 exponentA, int256 exponentB) external pure {
        exponentA = bound(exponentA, EXPONENT_MIN, EXPONENT_MAX);
        exponentB = bound(exponentB, EXPONENT_MIN, EXPONENT_MAX);

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
