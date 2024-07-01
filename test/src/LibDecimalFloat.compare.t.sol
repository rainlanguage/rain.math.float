// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, COMPARE_EQUAL, COMPARE_GREATER_THAN} from "src/lib/LibDecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatCompareTest is Test {
    /// 1 == 1
    function testCompareOne() external pure {
        int256 compare = LibDecimalFloat.compare(1, 0, 1, 0);
        assertEq(compare, COMPARE_EQUAL);
    }

    /// 10,0 == 1e38,-37
    function testCompareTen() external pure {
        int256 compare = LibDecimalFloat.compare(10, 0, 1e38, -37);
        assertEq(compare, COMPARE_EQUAL);
    }

    /// 1.6e35,-35 > 1.25e37,-37
    function testCompareOnePointSix() external pure {
        int256 compare = LibDecimalFloat.compare(1.6e35, -35, 1.25e37, -37);
        assertEq(compare, COMPARE_GREATER_THAN);
    }
}
