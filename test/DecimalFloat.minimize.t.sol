// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat} from "src/DecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract DecimalFloatMinimizeTest is Test {
    // /// 1 => 1
    // function testMinimize1() external pure {
    //     (int256 minimizedCoefficient, int256 minimizedExponent) = LibDecimalFloat.minimize(1, 0);
    //     assertEq(minimizedCoefficient, 1, "coefficient");
    //     assertEq(minimizedExponent, 0, "exponent");
    // }

    // /// 1e18 => 1e38
    // function testMinimize1e18() external pure {
    //     (int256 minimizedCoefficient, int256 minimizedExponent) = LibDecimalFloat.minimize(1e18, 0);
    //     assertEq(minimizedCoefficient, 1, "coefficient");
    //     assertEq(minimizedExponent, 18, "exponent");
    // }
}
