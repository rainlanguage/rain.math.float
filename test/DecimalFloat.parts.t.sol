// SPDX-License-Identifier: CAL
pragma solidity ^0.8.25;

import {LibDecimalFloat, COEFFICIENT_MASK, ExponentOverflow} from "src/DecimalFloat.sol";
import {Test} from "forge-std/Test.sol";

contract DecimalFloatPartsTest is Test {
    // /// Round trip from/to parts.
    // function testPartsRoundTrip(int128 signedCoefficient, int128 exponent) external pure {
    //     DecimalFloat value = LibDecimalFloat.fromParts(signedCoefficient, exponent);
    //     (int128 signedCoefficientOut, int128 exponentOut) = value.toParts();
    //     assertEq(signedCoefficient, signedCoefficientOut, "coefficient");
    //     assertEq(exponent, exponentOut, "exponent");
    // }
}
