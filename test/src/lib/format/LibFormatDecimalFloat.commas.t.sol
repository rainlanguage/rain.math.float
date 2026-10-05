// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Float, LibDecimalFloat} from "src/lib/LibDecimalFloat.sol";
import {LibFormatDecimalFloat} from "src/lib/format/LibFormatDecimalFloat.sol";
import {LibParseDecimalFloat} from "src/lib/parse/LibParseDecimalFloat.sol";

contract LibFormatDecimalFloatCommasTest is Test {
    using LibDecimalFloat for Float;

    function checkCommas(int256 signedCoefficient, int256 exponent, string memory expected) internal pure {
        Float float = LibDecimalFloat.packLossless(signedCoefficient, exponent);
        assertEq(LibFormatDecimalFloat.toDecimalString(float, false, true), expected, "formatted");
        (bytes4 errorSelector, Float parsed) = LibParseDecimalFloat.parseDecimalFloat(expected, true);
        assertEq(errorSelector, bytes4(0), "parse");
        assertTrue(parsed.eq(float), "round trip");
    }

    function withoutCommas(string memory str) internal pure returns (string memory) {
        bytes memory input = bytes(str);
        bytes memory out = new bytes(input.length);
        uint256 length = 0;
        for (uint256 i = 0; i < input.length; i++) {
            if (input[i] != ",") {
                out[length++] = input[i];
            }
        }
        assembly ("memory-safe") {
            mstore(out, length)
        }
        return string(out);
    }

    function testFormatCommasExamples() external pure {
        checkCommas(0, 0, "0");
        checkCommas(1, 0, "1");
        checkCommas(999, 0, "999");
        checkCommas(-999, 0, "-999");
        checkCommas(1000, 0, "1,000");
        checkCommas(-1000, 0, "-1,000");
        checkCommas(12345, 0, "12,345");
        checkCommas(123456, 0, "123,456");
        checkCommas(1234567, 0, "1,234,567");
        checkCommas(-123456789, -2, "-1,234,567.89");
        checkCommas(1, 3, "1,000");
        checkCommas(1, 6, "1,000,000");
        checkCommas(12345678, -4, "1,234.5678");
        checkCommas(999999, -3, "999.999");
        checkCommas(1, -3, "0.001");
        checkCommas(-5, -1, "-0.5");
    }

    function testFormatCommasScientificUnchanged() external pure {
        Float float = LibDecimalFloat.packLossless(1234567, 0);
        assertEq(LibFormatDecimalFloat.toDecimalString(float, true, true), "1.234567e6");
        assertEq(LibFormatDecimalFloat.toDecimalString(float, true, false), "1.234567e6");
    }

    /// Grouping only inserts commas: removing them recovers the ungrouped
    /// string, which the commas=false overload returns unchanged, and the
    /// grouped string parses back to the same value.
    function testFormatCommasFuzz(int224 coefficient, int32 exponent, bool scientific) external pure {
        int256 boundedExponent = bound(exponent, -60, 0);
        Float float = LibDecimalFloat.packLossless(coefficient, boundedExponent);
        string memory plain = LibFormatDecimalFloat.toDecimalString(float, scientific);
        assertEq(LibFormatDecimalFloat.toDecimalString(float, scientific, false), plain, "commas false");
        string memory commas = LibFormatDecimalFloat.toDecimalString(float, scientific, true);
        assertEq(withoutCommas(commas), plain, "only commas inserted");

        bytes memory b = bytes(commas);
        uint256 intEnd = 0;
        while (intEnd < b.length && b[intEnd] != "." && b[intEnd] != "e") {
            intEnd++;
        }
        uint256 intStart = b[0] == "-" ? 1 : 0;
        assertTrue(b[intStart] != ",", "leading comma");
        for (uint256 i = intStart; i < intEnd; i++) {
            assertEq(b[i] == ",", (intEnd - i) % 4 == 0, "comma every three digits");
        }
        for (uint256 i = intEnd; i < b.length; i++) {
            assertTrue(b[i] != ",", "comma outside integer part");
        }

        (bytes4 errorSelector, Float parsed) = LibParseDecimalFloat.parseDecimalFloat(commas, true);
        assertEq(errorSelector, bytes4(0), "parse");
        assertTrue(parsed.eq(float), "round trip");
    }
}
