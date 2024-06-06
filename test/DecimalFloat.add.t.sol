// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {DecimalFloat, LibDecimalFloat, COMPARE_EQUAL} from "src/DecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract DecimalFloatDecimalTest is Test {
    using LibDecimalFloat for DecimalFloat;

    /// Simple 0 add 0
    /// 0 + 0 = 0
    function testAddZero() external pure {
        DecimalFloat a = LibDecimalFloat.fromParts(0, 0);
        DecimalFloat b = LibDecimalFloat.fromParts(0, 0);
        DecimalFloat actual = a.add(b);
        DecimalFloat expected = LibDecimalFloat.fromParts(0, 0);
        assertEq(DecimalFloat.unwrap(actual), DecimalFloat.unwrap(expected));
    }

    /// 0 add 0 any exponent
    /// 0 + 0 = 0
    function testAddZeroAnyExponent(int128 exponent) external pure {
        DecimalFloat a = LibDecimalFloat.fromParts(0, exponent);
        DecimalFloat b = LibDecimalFloat.fromParts(0, 0);
        DecimalFloat actual = a.add(b);
        DecimalFloat expected = LibDecimalFloat.fromParts(0, 0);
        assertEq(actual.compare(expected), COMPARE_EQUAL);
    }

    /// 0 add 1
    /// 0 + 1 = 1
    function testAddZeroOne() external pure {
        DecimalFloat a = LibDecimalFloat.fromParts(0, 0);
        DecimalFloat b = LibDecimalFloat.fromParts(1, 0);
        DecimalFloat actual = a.add(b);
        DecimalFloat expected = LibDecimalFloat.fromParts(1, 0);
        assertEq(DecimalFloat.unwrap(actual), DecimalFloat.unwrap(expected));
    }

    /// 1 add 0
    /// 1 + 0 = 1
    function testAddOneZero() external pure {
        DecimalFloat a = LibDecimalFloat.fromParts(1, 0);
        DecimalFloat b = LibDecimalFloat.fromParts(0, 0);
        DecimalFloat actual = a.add(b);
        DecimalFloat expected = LibDecimalFloat.fromParts(1, 0);
        assertEq(DecimalFloat.unwrap(actual), DecimalFloat.unwrap(expected));
    }

    /// 1 add 1
    /// 1 + 1 = 2
    function testAddOneOne() external pure {
        DecimalFloat a = LibDecimalFloat.fromParts(1, 0);
        DecimalFloat b = LibDecimalFloat.fromParts(1, 0);
        DecimalFloat actual = a.add(b);
        DecimalFloat expected = LibDecimalFloat.fromParts(2, 0);
        assertEq(DecimalFloat.unwrap(actual), DecimalFloat.unwrap(expected));
    }

    /// 123456789 add 987654321
    /// 123456789 + 987654321 = 1111111110
    function testAdd123456789987654321() external pure {
        DecimalFloat a = LibDecimalFloat.fromParts(123456789, 0);
        DecimalFloat b = LibDecimalFloat.fromParts(987654321, 0);
        DecimalFloat actual = a.add(b);
        DecimalFloat expected = LibDecimalFloat.fromParts(1111111110, 0);
        assertEq(DecimalFloat.unwrap(actual), DecimalFloat.unwrap(expected));
    }

    /// 123456789e9 add 987654321
    /// 123456789e9 + 987654321 = 123456789987654321
    function testAdd123456789e9987654321() external pure {
        DecimalFloat a = LibDecimalFloat.fromParts(123456789, 9);
        DecimalFloat b = LibDecimalFloat.fromParts(987654321, 0);
        DecimalFloat actual = a.add(b);
        DecimalFloat expected = LibDecimalFloat.fromParts(123456789987654321, 0);
        assertEq(DecimalFloat.unwrap(actual), DecimalFloat.unwrap(expected));
    }

    function testGasAddZero() external pure {
        DecimalFloat.wrap(0).add(DecimalFloat.wrap(0));
    }

    function testGasAddOne() external pure {
        DecimalFloat.wrap(1).add(DecimalFloat.wrap(1));
    }
}
