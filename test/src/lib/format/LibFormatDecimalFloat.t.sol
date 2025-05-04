// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 thedavidmeister
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {Float, LibDecimalFloat} from "src/lib/LibDecimalFloat.sol";
import {LibFormatDecimalFloat} from "src/lib/format/LibFormatDecimalFloat.sol";
import {LibParseDecimalFloat} from "src/lib/parse/LibParseDecimalFloat.sol";

/// @title LibFormatDecimalFloatTest
/// @notice Test contract for verifying the functionality of LibFormatDecimalFloat
/// @dev Tests both the stack and memory versions of formatting functions and round-trip conversions
contract LibFormatDecimalFloatTest is Test {
    using LibDecimalFloat for Float;
    using LibFormatDecimalFloat for Float;

    function toDecimalStringExternal(int256 signedCoefficient, int256 exponent) external pure returns (string memory) {
        return LibFormatDecimalFloat.toDecimalString(signedCoefficient, exponent);
    }

    function toString(Float float) external pure returns (string memory) {
        return LibFormatDecimalFloat.toDecimalString(float);
    }

    /// Check that the memory version matches the stack version.
    function testFormatMem(Float float) external {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        try this.toDecimalStringExternal(signedCoefficient, exponent) returns (string memory formatted) {
            string memory actual = this.toString(float);
            assertEq(formatted, actual, "Formatted value mismatch");
        } catch (bytes memory err) {
            vm.expectRevert(err);
            LibFormatDecimalFloat.toDecimalString(float);
        }
    }

    /// Test round tripping a value through parse and format.
    function testFormatDecimalRoundTrip(uint256 value) external pure {
        value = bound(value, 0, uint256(int256(type(int224).max)));
        Float float = LibDecimalFloat.fromFixedDecimalLosslessPacked(value, 18);
        string memory formatted = LibFormatDecimalFloat.toDecimalString(float);
        (bytes4 errorCode, Float parsed) = LibParseDecimalFloat.parseDecimalFloat(formatted);
        assertEq(errorCode, 0, "Parse error");
        assertTrue(float.eq(parsed), "Round trip failed");
    }

    /// Negative matches positive.
    function testFormatDecimalRoundTripNegative(int256 value) external pure {
        value = bound(value, 1, int256(type(int128).max));
        Float float = LibDecimalFloat.packLossless(value, 18);
        string memory formatted = float.toDecimalString();
        float = float.minus();
        string memory formattedNeg = float.toDecimalString();

        assertEq(string.concat("-", formatted), formattedNeg, "Negative format mismatch");
    }

    /// Test some specific examples.
    function testFormatDecimalExamples() external pure {
        // pos decs
        assertEq(
            LibFormatDecimalFloat.toDecimalString(123456789012345678901234567890, 0), "123456789012345678901234567890"
        );
        assertEq(
            LibFormatDecimalFloat.toDecimalString(123456789012345678901234567890, -1), "12345678901234567890123456789"
        );
        assertEq(
            LibFormatDecimalFloat.toDecimalString(123456789012345678901234567890, -2), "1234567890123456789012345678.9"
        );
        assertEq(
            LibFormatDecimalFloat.toDecimalString(123456789012345678901234567890, -3), "123456789012345678901234567.89"
        );
        assertEq(
            LibFormatDecimalFloat.toDecimalString(123456789012345678901234567890, -4), "12345678901234567890123456.789"
        );
        assertEq(
            LibFormatDecimalFloat.toDecimalString(123456789012345678901234567890, -5), "1234567890123456789012345.6789"
        );
        assertEq(
            LibFormatDecimalFloat.toDecimalString(123456789012345678901234567890, -6), "123456789012345678901234.56789"
        );

        // zeros
        assertEq(LibFormatDecimalFloat.toDecimalString(0, 0), "0");
        assertEq(LibFormatDecimalFloat.toDecimalString(0, -1), "0");
        assertEq(LibFormatDecimalFloat.toDecimalString(0, -2), "0");
        assertEq(LibFormatDecimalFloat.toDecimalString(0, -3), "0");
        assertEq(LibFormatDecimalFloat.toDecimalString(0, 1), "0");
        assertEq(LibFormatDecimalFloat.toDecimalString(0, 2), "0");
        assertEq(LibFormatDecimalFloat.toDecimalString(0, 3), "0");

        // neg decs
        assertEq(
            LibFormatDecimalFloat.toDecimalString(-123456789012345678901234567890, 0), "-123456789012345678901234567890"
        );
        assertEq(
            LibFormatDecimalFloat.toDecimalString(-123456789012345678901234567890, -1), "-12345678901234567890123456789"
        );
        assertEq(
            LibFormatDecimalFloat.toDecimalString(-123456789012345678901234567890, -2),
            "-1234567890123456789012345678.9"
        );
        assertEq(
            LibFormatDecimalFloat.toDecimalString(-123456789012345678901234567890, -3),
            "-123456789012345678901234567.89"
        );
        assertEq(
            LibFormatDecimalFloat.toDecimalString(-123456789012345678901234567890, -4),
            "-12345678901234567890123456.789"
        );
        assertEq(
            LibFormatDecimalFloat.toDecimalString(-123456789012345678901234567890, -5),
            "-1234567890123456789012345.6789"
        );
        assertEq(
            LibFormatDecimalFloat.toDecimalString(-123456789012345678901234567890, -6),
            "-123456789012345678901234.56789"
        );
    }
}
