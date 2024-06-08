// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, COMPARE_EQUAL} from "src/DecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract DecimalFloatMultiplyTest is Test {
// /// Simple 0 multiply 0
// /// 0 * 0 = 0
// function testMultiplyZero0Exponent() external pure {
//     DecimalFloat a = LibDecimalFloat.fromParts(0, 0);
//     DecimalFloat b = LibDecimalFloat.fromParts(0, 0);
//     DecimalFloat actual = a.multiply(b);
//     DecimalFloat expected = LibDecimalFloat.fromParts(0, 0);
//     assertEq(actual.compare(expected), COMPARE_EQUAL);
// }

// /// 0 multiply 0 any exponent
// /// 0 * 0 = 0
// function testMultiplyZeroAnyExponent(int64 exponentA, int64 exponentB) external pure {
//     DecimalFloat a = LibDecimalFloat.fromParts(0, exponentA);
//     DecimalFloat b = LibDecimalFloat.fromParts(0, exponentB);
//     DecimalFloat actual = a.multiply(b);
//     DecimalFloat expected = LibDecimalFloat.fromParts(0, 0);
//     assertEq(actual.compare(expected), COMPARE_EQUAL);
// }

// /// 0 multiply 1
// /// 0 * 1 = 0
// function testMultiplyZeroOne() external pure {
//     DecimalFloat a = LibDecimalFloat.fromParts(0, 0);
//     DecimalFloat b = LibDecimalFloat.fromParts(1, 0);
//     DecimalFloat actual = a.multiply(b);
//     DecimalFloat expected = LibDecimalFloat.fromParts(0, 0);
//     assertEq(DecimalFloat.unwrap(actual), DecimalFloat.unwrap(expected));
// }

// /// 1 multiply 0
// /// 1 * 0 = 0
// function testMultiplyOneZero() external pure {
//     DecimalFloat a = LibDecimalFloat.fromParts(1, 0);
//     DecimalFloat b = LibDecimalFloat.fromParts(0, 0);
//     DecimalFloat actual = a.multiply(b);
//     DecimalFloat expected = LibDecimalFloat.fromParts(0, 0);
//     assertEq(DecimalFloat.unwrap(actual), DecimalFloat.unwrap(expected));
// }

// /// 1 multiply 1
// /// 1 * 1 = 1
// function testMultiplyOneOne() external pure {
//     DecimalFloat a = LibDecimalFloat.fromParts(1, 0);
//     DecimalFloat b = LibDecimalFloat.fromParts(1, 0);
//     DecimalFloat actual = a.multiply(b);
//     DecimalFloat expected = LibDecimalFloat.fromParts(1, 0);
//     assertEq(DecimalFloat.unwrap(actual), DecimalFloat.unwrap(expected));
// }

// /// 123456789 multiply 987654321
// /// 123456789 * 987654321 = 121932631112635269
// function testMultiply123456789987654321() external pure {
//     DecimalFloat a = LibDecimalFloat.fromParts(123456789, 0);
//     DecimalFloat b = LibDecimalFloat.fromParts(987654321, 0);
//     DecimalFloat actual = a.multiply(b);
//     DecimalFloat expected = LibDecimalFloat.fromParts(121932631112635269, 0);
//     assertEq(DecimalFloat.unwrap(actual), DecimalFloat.unwrap(expected));
// }

// /// 123456789 multiply 987654321 with exponents
// /// 123456789 * 987654321 = 121932631112635269
// function testMultiply123456789987654321WithExponents(int128 exponentA, int128 exponentB) external pure {
//     exponentA = int128(bound(exponentA, -127, 127));
//     exponentB = int128(bound(exponentB, -127, 127));

//     DecimalFloat a = LibDecimalFloat.fromParts(123456789, exponentA);
//     DecimalFloat b = LibDecimalFloat.fromParts(987654321, exponentB);
//     DecimalFloat actual = a.multiply(b);
//     DecimalFloat expected = LibDecimalFloat.fromParts(121932631112635269, exponentA + exponentB);
//     assertEq(DecimalFloat.unwrap(actual), DecimalFloat.unwrap(expected));
// }

// /// 1e18 * 1e-19 = 1e-1
// function testMultiply1e181e19() external pure {
//     DecimalFloat a = LibDecimalFloat.fromParts(1, 18);
//     DecimalFloat b = LibDecimalFloat.fromParts(1, -19);
//     DecimalFloat actual = a.multiply(b);
//     DecimalFloat expected = LibDecimalFloat.fromParts(1, -1);
//     assertEq(DecimalFloat.unwrap(actual), DecimalFloat.unwrap(expected));
// }

// function testMultipleGasZero() external pure {
//     DecimalFloat.wrap(0).multiply(DecimalFloat.wrap(0));
// }

// function testMultipleGasOne() external pure {
//     DecimalFloat.wrap(1).multiply(DecimalFloat.wrap(1));
// }
}
