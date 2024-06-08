// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, COMPARE_EQUAL} from "src/DecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract DecimalFloatCompareTest is Test {
    // /// 1 == 1
    // function testCompareOne() external pure {
    //     DecimalFloat a = DecimalFloat.wrap(1);
    //     DecimalFloat b = DecimalFloat.wrap(1);
    //     assertEq(a.compare(b), COMPARE_EQUAL);
    // }

    // /// 10,0 == 1e38,-37
    // function testCompareTen() external pure {
    //     DecimalFloat a = LibDecimalFloat.fromParts(10, 0);
    //     DecimalFloat b = LibDecimalFloat.fromParts(1e38, -37);
    //     assertEq(a.compare(b), COMPARE_EQUAL);
    // }

    // /// 1.6e35,-35 > 1.25e37,-37
    // function testCompareOnePointSix() external pure {
    //     DecimalFloat a = LibDecimalFloat.fromParts(1.6e35, -35);
    //     DecimalFloat b = LibDecimalFloat.fromParts(1.25e37, -37);
    //     assertEq(a.compare(b), 1);
    // }
}
