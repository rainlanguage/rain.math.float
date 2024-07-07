// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, COMPARE_EQUAL, EXPONENT_MIN, EXPONENT_MAX} from "src/lib/LibDecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatDecimalTest is Test {
    /// Simple 0 add 0
    /// 0 + 0 = 0
    function testAddZero() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.add(0, 0, 0, 0);
        assertEq(signedCoefficient, 0);
        assertEq(exponent, -37);
    }

    /// 0 add 0 any exponent
    /// 0 + 0 = 0
    function testAddZeroAnyExponent(int128 inputExponent) external pure {
        inputExponent = int128(bound(inputExponent, EXPONENT_MIN, EXPONENT_MAX));
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.add(0, inputExponent, 0, 0);
        assertEq(signedCoefficient, 0);
        assertEq(exponent, -37);
    }

    /// 0 add 1
    /// 0 + 1 = 1
    function testAddZeroOne() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.add(0, 0, 1, 0);
        assertEq(signedCoefficient, 1e37);
        assertEq(exponent, -37);
    }

    /// 1 add 0
    /// 1 + 0 = 1
    function testAddOneZero() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.add(1, 0, 0, 0);
        assertEq(signedCoefficient, 1e37);
        assertEq(exponent, -37);
    }

    /// 1 add 1
    /// 1 + 1 = 2
    function testAddOneOne() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.add(1, 0, 1, 0);
        assertEq(signedCoefficient, 2e37);
        assertEq(exponent, -37);
    }

    /// 123456789 add 987654321
    /// 123456789 + 987654321 = 1111111110
    function testAdd123456789987654321() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.add(123456789, 0, 987654321, 0);
        assertEq(signedCoefficient, 1.11111111e37);
        assertEq(exponent, -28);
    }

    /// 123456789e9 add 987654321
    /// 123456789e9 + 987654321 = 123456789987654321
    function testAdd123456789e9987654321() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.add(123456789, 9, 987654321, 0);
        assertEq(signedCoefficient, 1.23456789987654321e37);
        assertEq(exponent, -20);
    }

    function testGasAddZero() external pure {
        LibDecimalFloat.add(0, 0, 0, 0);
    }

    function testGasAddOne() external pure {
        LibDecimalFloat.add(1e37, -37, 1e37, -37);
    }
}
