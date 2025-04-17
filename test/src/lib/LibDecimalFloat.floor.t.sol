// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatFloorTest is Test {
    using LibDecimalFloat for Float;

    function floorExternal(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloat.floor(signedCoefficient, exponent);
    }

    function floorExternal(Float float) external pure returns (Float) {
        return LibDecimalFloat.floor(float);
    }
    /// Stack and mem are the same.

    function testFloorMem(Float float) external {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        try this.floorExternal(signedCoefficient, exponent) returns (
            int256 signedCoefficientFloor, int256 exponentFloor
        ) {
            Float floatFloor = this.floorExternal(float);
            (int256 signedCoefficientFloorUnpacked, int256 exponentFloorUnpacked) = floatFloor.unpack();
            assertEq(signedCoefficientFloor, signedCoefficientFloorUnpacked);
            assertEq(exponentFloor, exponentFloorUnpacked);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.floorExternal(float);
        }
    }

    function testFloorNotReverts(int256 x, int256 exponentX) external pure {
        LibDecimalFloat.floor(x, exponentX);
    }

    function checkFloor(int256 x, int256 exponent, int256 expectedFrac, int256 expectedFracExponent) internal pure {
        (x, exponent) = LibDecimalFloat.floor(x, exponent);
        assertEq(x, expectedFrac);
        assertEq(exponent, expectedFracExponent);
    }

    /// Every non negative exponent is identity for floor.
    function testFloorNonNegative(int256 x, int256 exponent) external pure {
        exponent = bound(exponent, 0, type(int256).max);
        checkFloor(x, exponent, x, exponent);
    }

    /// If the exponent is less than -76 then the floor is 0.
    function testFloorLessThanMin(int256 x, int256 exponent) external pure {
        exponent = bound(exponent, type(int256).min, -77);
        checkFloor(x, exponent, 0, exponent);
    }

    /// For exponents [-76,-1] the floor is the / 1.
    function testFloorInRange(int256 x, int256 exponent) external pure {
        exponent = bound(exponent, -76, -1);
        int256 scale = int256(10 ** uint256(-exponent));
        checkFloor(x, exponent, (x / scale) * scale, exponent);
    }

    /// Examples
    function testFloorExamples() external pure {
        checkFloor(123456789, 0, 123456789, 0);
        checkFloor(123456789, -1, 123456780, -1);
        checkFloor(123456789, -2, 123456700, -2);
        checkFloor(123456789, -3, 123456000, -3);
        checkFloor(123456789, -4, 123450000, -4);
        checkFloor(123456789, -5, 123400000, -5);
        checkFloor(123456789, -6, 123000000, -6);
        checkFloor(123456789, -7, 120000000, -7);
        checkFloor(123456789, -8, 100000000, -8);
        checkFloor(123456789, -9, 0, -9);
        checkFloor(123456789, -10, 0, -10);
        checkFloor(123456789, -11, 0, -11);
        checkFloor(type(int256).max, 0, type(int256).max, 0);
        checkFloor(type(int256).min, 0, type(int256).min, 0);

        checkFloor(2.5e37, -37, 2e37, -37);

        checkFloor(type(int256).max, 0, type(int256).max, 0);
        checkFloor(
            type(int256).max, -1, 57896044618658097711785492504343953926634992332820282019728792003956564819960, -1
        );
        checkFloor(
            type(int256).max, -2, 57896044618658097711785492504343953926634992332820282019728792003956564819900, -2
        );
        checkFloor(
            type(int256).max, -3, 57896044618658097711785492504343953926634992332820282019728792003956564819000, -3
        );
        checkFloor(
            type(int256).max, -4, 57896044618658097711785492504343953926634992332820282019728792003956564810000, -4
        );
        checkFloor(type(int256).max, -77, 0, -77);
        checkFloor(type(int256).max, -78, 0, -78);
        checkFloor(type(int256).max, -76, 5e76, -76);
    }

    function testFloorGasZero() external pure {
        LibDecimalFloat.floor(0, 0);
    }

    function testFloorGasTiny() external pure {
        LibDecimalFloat.floor(1, -100);
    }

    function testFloorGas0() external pure {
        LibDecimalFloat.floor(2.5e37, -37);
    }
}
