// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";

import {LibParseDecimalFloat} from "src/lib/parse/LibParseDecimalFloat.sol";
import {LibBytes, Pointer} from "rain.solmem/lib/LibBytes.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

contract LibParseDecimalFloatTest is Test {
    using LibBytes for bytes;
    using Strings for uint256;

    function checkParseDecimalFloat(
        string memory data,
        int256 expectedSignedCoefficient,
        int256 expectedExponent,
        uint256 expectedCursorAfter
    ) internal pure {
        uint256 cursor = Pointer.unwrap(bytes(data).dataPointer());
        (bytes4 errorSelector, uint256 cursorAfter, int256 signedCoefficient, int256 exponent) =
        LibParseDecimalFloat.parseDecimalFloat(cursor, Pointer.unwrap(bytes(data).endDataPointer()));
        assertEq(errorSelector, bytes4(0));
        assertEq(signedCoefficient, expectedSignedCoefficient);
        assertEq(exponent, expectedExponent);
        assertEq(cursorAfter - cursor, expectedCursorAfter);
    }

    /// Fuzz and round trip.
    function testParseLiteralDecimalFloatFuzz(uint256 value, uint8 leadingZerosCount, bool isNeg) external pure {
        value = bound(value, 0, uint256(type(int256).max) + (isNeg ? 1 : 0));
        string memory str = value.toString();

        string memory leadingZeros = new string(leadingZerosCount);
        for (uint8 i = 0; i < leadingZerosCount; i++) {
            bytes(leadingZeros)[i] = "0";
        }

        string memory input = string(abi.encodePacked((isNeg ? "-" : ""), leadingZeros, str));

        checkParseDecimalFloat(
            input,
            isNeg ? (value == (uint256(type(int256).max) + 1) ? type(int256).min : -int256(value)) : int256(value),
            0,
            bytes(input).length
        );
    }

    /// Check some specific examples.
    function testParseLiteralDecimalFloatSpecific() external pure {
        checkParseDecimalFloat("0", 0, 0, 1);
        checkParseDecimalFloat("1", 1, 0, 1);
        checkParseDecimalFloat("10", 10, 0, 2);
        checkParseDecimalFloat("100", 100, 0, 3);
        checkParseDecimalFloat("1000", 1000, 0, 4);
        checkParseDecimalFloat("2", 2, 0, 1);
    }

    /// Check some specific examples with leading zeros.
    function testParseLiteralDecimalFloatLeadingZeros() external pure {
        checkParseDecimalFloat("0000", 0, 0, 4);
        checkParseDecimalFloat("0001", 1, 0, 4);
        checkParseDecimalFloat("0010", 10, 0, 4);
        checkParseDecimalFloat("0100", 100, 0, 4);
        checkParseDecimalFloat("1000", 1000, 0, 4);
        checkParseDecimalFloat("0002", 2, 0, 4);
        checkParseDecimalFloat(
            "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001",
            1,
            0,
            128
        );
    }

    /// Check some examples of decimals.
    function testParseLiteralDecimalFloatDecimals() external pure {
        checkParseDecimalFloat("0.1", 1, -1, 3);
        checkParseDecimalFloat("0.01", 1, -2, 4);
        checkParseDecimalFloat("0.001", 1, -3, 5);
        checkParseDecimalFloat("0.0001", 1, -4, 6);
        checkParseDecimalFloat("0.00001", 1, -5, 7);
        checkParseDecimalFloat("0.000001", 1, -6, 8);
        checkParseDecimalFloat("0.0000001", 1, -7, 9);
        checkParseDecimalFloat("0.00000001", 1, -8, 10);
        checkParseDecimalFloat("0.000000001", 1, -9, 11);
        checkParseDecimalFloat("0.0000000001", 1, -10, 12);
        checkParseDecimalFloat("0.00000000001", 1, -11, 13);
        checkParseDecimalFloat("0.000000000001", 1, -12, 14);
        checkParseDecimalFloat("0.0000000000001", 1, -13, 15);
        checkParseDecimalFloat("0.00000000000001", 1, -14, 16);
        checkParseDecimalFloat("0.000000000000001", 1, -15, 17);
        checkParseDecimalFloat("0.0000000000000001", 1, -16, 18);
        checkParseDecimalFloat("0.00000000000000001", 1, -17, 19);
        checkParseDecimalFloat("0.000000000000000001", 1, -18, 20);
        checkParseDecimalFloat("0.0000000000000000001", 1, -19, 21);
        checkParseDecimalFloat("0.00000000000000000001", 1, -20, 22);
        checkParseDecimalFloat("0.000000000000000000001", 1, -21, 23);
        checkParseDecimalFloat("0.0000000000000000000001", 1, -22, 24);
        checkParseDecimalFloat(
            "0.0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001",
            1,
            -127,
            129
        );
        checkParseDecimalFloat(
            "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000.0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001",
            1,
            -127,
            254
        );

        checkParseDecimalFloat("1.1", 11, -1, 3);
        checkParseDecimalFloat("1.01", 101, -2, 4);
        checkParseDecimalFloat("1.001", 1001, -3, 5);
        checkParseDecimalFloat("1.0001", 10001, -4, 6);
        checkParseDecimalFloat("1.0001", 10001, -4, 6);

        checkParseDecimalFloat("10.1", 101, -1, 4);
        checkParseDecimalFloat("10.01", 1001, -2, 5);
        checkParseDecimalFloat("10.001", 10001, -3, 6);
        checkParseDecimalFloat("10.0001", 100001, -4, 7);

        checkParseDecimalFloat("100.1", 1001, -1, 5);
        checkParseDecimalFloat("100.01", 10001, -2, 6);
        // some trailing zeros
        checkParseDecimalFloat("100.001000", 100001, -3, 10);
        checkParseDecimalFloat(
            "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100.0001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
            1000001,
            -4,
            260
        );
    }

    /// Check some examples of exponents.
    function testParseLiteralDecimalFloatExponents() external pure {
        // checkParseDecimalFloat("0e0", 0, 0, 3);
        // // A capital E.
        // checkParseDecimalFloat("0E0", 0, 0, 3);
        // checkParseDecimalFloat("0e1", 0, 1, 3);
        // checkParseDecimalFloat("0e2", 0, 2, 3);
        // checkParseDecimalFloat("0e-1", 0, -1, 4);
        // checkParseDecimalFloat("0e-2", 0, -2, 4);

        // checkParseDecimalFloat("1e1", 1, 1, 3);
        // checkParseDecimalFloat("1e2", 1, 2, 3);
        // checkParseDecimalFloat("1e3", 1, 3, 3);
        // checkParseDecimalFloat("1e4", 1, 4, 3);
        // checkParseDecimalFloat("1e5", 1, 5, 3);
        // checkParseDecimalFloat("1e6", 1, 6, 3);
        // checkParseDecimalFloat("1e7", 1, 7, 3);
        // checkParseDecimalFloat("1e8", 1, 8, 3);
        // checkParseDecimalFloat("1e9", 1, 9, 3);
        // checkParseDecimalFloat("1e10", 1, 10, 4);
        // checkParseDecimalFloat("1e11", 1, 11, 4);
        // checkParseDecimalFloat("1e12", 1, 12, 4);
        // checkParseDecimalFloat("1e13", 1, 13, 4);
        // checkParseDecimalFloat("1e14", 1, 14, 4);
        // checkParseDecimalFloat("1e15", 1, 15, 4);
        // checkParseDecimalFloat("1e16", 1, 16, 4);
        // checkParseDecimalFloat("1e17", 1, 17, 4);
        // checkParseDecimalFloat("1e18", 1, 18, 4);
        // checkParseDecimalFloat("1e19", 1, 19, 4);
        // checkParseDecimalFloat("1e20", 1, 20, 4);
        // checkParseDecimalFloat("1e21", 1, 21, 4);
        // checkParseDecimalFloat("1e22", 1, 22, 4);
        // checkParseDecimalFloat("1e23", 1, 23, 4);
        // checkParseDecimalFloat("1e24", 1, 24, 4);
        // checkParseDecimalFloat("1e25", 1, 25, 4);
        // checkParseDecimalFloat("1e26", 1, 26, 4);
        // checkParseDecimalFloat("1e260", 1, 260, 5);

        // checkParseDecimalFloat("1e0", 1, 0, 3);
        // // A capital E.
        // checkParseDecimalFloat("1E0", 1, 0, 3);
        // checkParseDecimalFloat("1e-0", 1, 0, 4);
        // // A capital E.
        // checkParseDecimalFloat("1E-0", 1, 0, 4);

        // checkParseDecimalFloat("1e-1", 1, -1, 4);
        // checkParseDecimalFloat("1e-2", 1, -2, 4);
        // checkParseDecimalFloat("1e-3", 1, -3, 4);
        // checkParseDecimalFloat("1e-4", 1, -4, 4);
        // checkParseDecimalFloat("1e-5", 1, -5, 4);
        // checkParseDecimalFloat("1e-6", 1, -6, 4);
        // checkParseDecimalFloat("1e-7", 1, -7, 4);
        // checkParseDecimalFloat("1e-8", 1, -8, 4);

        // checkParseDecimalFloat("1e-9912873918273981273918273918739182", 1, -9912873918273981273918273918739182, 37);
        // checkParseDecimalFloat("1e9912873918273981273918273918739182", 1, 9912873918273981273918273918739182, 36);
        // checkParseDecimalFloat(
        //     "1e57896044618658097711785492504343953926634992332820282019728792003956564819967", 1, type(int256).max, 79
        // );
        // checkParseDecimalFloat(
        //     "57896044618658097711785492504343953926634992332820282019728792003956564819967e57896044618658097711785492504343953926634992332820282019728792003956564819967",
        //     type(int256).max,
        //     type(int256).max,
        //     155
        // );
        // checkParseDecimalFloat(
        //     "1e-57896044618658097711785492504343953926634992332820282019728792003956564819968", 1, type(int256).min, 80
        // );
        // checkParseDecimalFloat(
        //     "-57896044618658097711785492504343953926634992332820282019728792003956564819968e-57896044618658097711785492504343953926634992332820282019728792003956564819968",
        //     type(int256).min,
        //     type(int256).min,
        //     157
        // );

        checkParseDecimalFloat("0.0e0", 0, 0, 5);
        // checkParseDecimalFloat("0.0e1", 0, 1, 5);
        // checkParseDecimalFloat("1.1e1", 11, 0, 5);
        // checkParseDecimalFloat("1.1e-1", 11, -2, 6);

        // // Some negatives.
        // checkParseDecimalFloat("-1.1e-1", -11, -2, 7);
        // checkParseDecimalFloat("-10.01e-1", -1001, -3, 9);
    }
}