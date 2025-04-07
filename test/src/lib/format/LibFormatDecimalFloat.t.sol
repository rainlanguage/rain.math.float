// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 thedavidmeister
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {Float, LibDecimalFloat} from "src/lib/LibDecimalFloat.sol";
import {LibFormatDecimalFloat} from "src/lib/format/LibFormatDecimalFloat.sol";
import {LibParseDecimalFloat} from "src/lib/parse/LibParseDecimalFloat.sol";

contract LibFormatDecimalFloatTest is Test {
    using LibDecimalFloat for Float;

    function toDecimalStringExternal(int256 signedCoefficient, int256 exponent) external pure returns (string memory) {
        return LibFormatDecimalFloat.toDecimalString(signedCoefficient, exponent);
    }

    function toString(Float memory float) external pure returns (string memory) {
        return LibFormatDecimalFloat.toDecimalString(float);
    }

    /// Check that the memory version matches the stack version.
    function testFormatMem(Float memory float) external {
        try this.toDecimalStringExternal(float.signedCoefficient, float.exponent) returns (string memory formatted) {
            string memory actual = this.toString(float);
            assertEq(formatted, actual, "Formatted value mismatch");
        } catch (bytes memory err) {
            vm.expectRevert(err);
            LibFormatDecimalFloat.toDecimalString(float);
        }
    }

    /// Test round tripping a value through parse and format.
    function testRoundTrip(uint256 value) external pure {
        // Dividing by 10 here keeps us clearly within the range of lossless
        // conversions.
        value = bound(value, 0, type(uint256).max / 10);
        Float memory float = LibDecimalFloat.fromFixedDecimalLosslessMem(value, 18);
        string memory formatted = LibFormatDecimalFloat.toDecimalString(float);
        (bytes4 errorCode, Float memory parsed) = LibParseDecimalFloat.parseDecimalFloat(formatted);
        assertEq(errorCode, 0, "Parse error");
        assertTrue(float.eq(parsed), "Round trip failed");
    }
}
