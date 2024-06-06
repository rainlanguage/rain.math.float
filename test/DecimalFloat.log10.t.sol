// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {DecimalFloat, LibDecimalFloat, COMPARE_EQUAL} from "src/DecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract DecimalFloatLog10Test is Test {
    using LibDecimalFloat for DecimalFloat;

    /// log10(1) = 0
    function testLog10One() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.log10ByParts(1, 0, 1);
        assertEq(signedCoefficient, 0);
        assertEq(exponent, 0);
    }
}