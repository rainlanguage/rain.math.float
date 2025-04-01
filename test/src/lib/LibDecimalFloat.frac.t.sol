// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatFracTest is Test {
    using LibDecimalFloat for Float;

    function fracExternal(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloat.frac(signedCoefficient, exponent);
    }

    function fracExternal(Float memory float) external pure returns (Float memory) {
        return LibDecimalFloat.frac(float);
    }
    /// Test to verify that stack-based and memory-based implementations produce the same results.
    function testFracMem(Float memory float) external {
        try this.fracExternal(float.signedCoefficient, float.exponent) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            Float memory floatFrac = this.fracExternal(float);
            assertEq(signedCoefficient, floatFrac.signedCoefficient);
            assertEq(exponent, floatFrac.exponent);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.fracExternal(float);
        }
    }

    function testFracNotReverts(int256 x, int256 exponentX) external pure {
        LibDecimalFloat.frac(x, exponentX);
    }

    function checkFrac(int256 x, int256 exponent, int256 expectedFrac, int256 expectedFracExponent) internal pure {
        (x, exponent) = LibDecimalFloat.frac(x, exponent);
        assertEq(x, expectedFrac);
        assertEq(exponent, expectedFracExponent);
    }

    /// Every non negative exponent has no fractional component.
    function testFracNonNegative(int256 x, int256 exponent) external pure {
        exponent = bound(exponent, 0, type(int256).max);
        checkFrac(x, exponent, 0, exponent);
    }

    /// If the exponent is less than -76 then the fractional component is the
    /// same as the input.
    function testFracLessThanMin(int256 x, int256 exponent) external pure {
        exponent = bound(exponent, type(int256).min, -77);
        checkFrac(x, exponent, x, exponent);
    }

    /// For exponents [-76,-1] the fractional component is the modulo of 1.
    function testFracInRange(int256 x, int256 exponent) external pure {
        exponent = bound(exponent, -76, -1);
        checkFrac(x, exponent, x % int256(10 ** uint256(-exponent)), exponent);
    }

    /// Examples
    function testFracExamples() external pure {
        checkFrac(123456789, 0, 0, 0);
        checkFrac(123456789, -1, 9, -1);
        checkFrac(123456789, -2, 89, -2);
        checkFrac(123456789, -3, 789, -3);
        checkFrac(123456789, -4, 6789, -4);
        checkFrac(123456789, -5, 56789, -5);
        checkFrac(123456789, -6, 456789, -6);
        checkFrac(123456789, -7, 3456789, -7);
        checkFrac(123456789, -8, 23456789, -8);
        checkFrac(123456789, -9, 123456789, -9);
        checkFrac(123456789, -10, 123456789, -10);
        checkFrac(123456789, -11, 123456789, -11);
        checkFrac(type(int256).max, 0, 0, 0);
        checkFrac(type(int256).min, 0, 0, 0);

        checkFrac(2.5e37, -37, 0.5e37, -37);

        checkFrac(type(int256).max, 0, 0, 0);
        checkFrac(type(int256).max, -1, 7, -1);
        checkFrac(type(int256).max, -2, 67, -2);
        checkFrac(type(int256).max, -3, 967, -3);
        checkFrac(type(int256).max, -4, 9967, -4);
        checkFrac(type(int256).max, -77, type(int256).max, -77);
        checkFrac(type(int256).max, -78, type(int256).max, -78);
        checkFrac(
            type(int256).max, -76, 7896044618658097711785492504343953926634992332820282019728792003956564819967, -76
        );
    }

    function testFracGasZero() external pure {
        LibDecimalFloat.frac(0, 0);
    }

    function testFracGasTiny() external pure {
        LibDecimalFloat.frac(1, -100);
    }

    function testFracGas0() external pure {
        LibDecimalFloat.frac(2.5e37, -37);
    }
}
