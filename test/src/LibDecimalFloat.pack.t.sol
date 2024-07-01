// SPDX-License-Identifier: CAL
pragma solidity ^0.8.25;

import {LibDecimalFloat, COEFFICIENT_MASK, ExponentOverflow} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatPackTest is Test {
    /// Round trip from/to parts.
    function testPartsRoundTrip(int128 signedCoefficient, int128 exponent) external pure {
        uint256 packed = LibDecimalFloat.pack(signedCoefficient, exponent);
        (int256 signedCoefficientOut, int256 exponentOut) = LibDecimalFloat.unpack(packed);

        assertEq(signedCoefficient, signedCoefficientOut, "coefficient");
        assertEq(exponent, exponentOut, "exponent");
    }
}
