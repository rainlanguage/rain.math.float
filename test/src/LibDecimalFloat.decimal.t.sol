// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, COEFFICIENT_MASK, ExponentOverflow, NORMALIZED_MAX} from "src/LibDecimalFloat.sol";

import {Test, console} from "forge-std/Test.sol";

contract LibDecimalFloatDecimalTest is Test {
    /// Round trip from/to decimal values without precision loss
    function testFixedDecimalRoundTripLossless(uint256 value, uint8 decimals) external pure {
        value = bound(value, 0, NORMALIZED_MAX);

        (int256 signedCoefficient, int256 exponent, bool lossless0) =
            LibDecimalFloat.fromFixedDecimalLossy(value, decimals);
        assertEq(lossless0, true, "lossless0");

        (uint256 valueOut, bool lossless1) = LibDecimalFloat.toFixedDecimalLossy(signedCoefficient, exponent, decimals);
        assertEq(value, valueOut, "value");
        assertEq(lossless1, true, "lossless1");
    }
}
