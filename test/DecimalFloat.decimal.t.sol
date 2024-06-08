// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, COEFFICIENT_MASK, ExponentOverflow} from "src/DecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract DecimalFloatDecimalTest is Test {

    // /// Round trip from/to decimal values without precision loss
    // function testDecimalRoundTrip(uint128 value, uint8 decimals) external pure {
    //     DecimalFloat decimal = LibDecimalFloat.fromFixedDecimal(value, decimals);
    //     uint256 valueOut = decimal.toFixedDecimal(decimals);
    //     assertEq(value, valueOut, "value");
    // }
}
