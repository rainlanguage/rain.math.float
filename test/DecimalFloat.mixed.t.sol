// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat} from "src/DecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract DecimalFloatMixedTest is Test {
    // /// (1 / 3) * 555e18
    // function testDivide1Over3() external pure {
    //     DecimalFloat a = LibDecimalFloat.fromParts(1, 0);
    //     DecimalFloat b = LibDecimalFloat.fromParts(3, 0);
    //     DecimalFloat c = LibDecimalFloat.fromParts(555, 18);
    //     DecimalFloat actual = a.divide(b).multiply(c);
    //     (int128 signedCoefficient, int128 exponent) = actual.toParts();
    //     assertEq(signedCoefficient, 18499999999999999999999999999999999999);
    //     assertEq(exponent, -17);
    // }
}
