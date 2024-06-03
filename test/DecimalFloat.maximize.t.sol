// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {DecimalFloat, LibDecimalFloat} from "src/DecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract DecimalFloatMaximizeTest is Test {
    using LibDecimalFloat for DecimalFloat;

    /// 1 => 1e38
    function testMaximize1() external pure {
        (int128 maximizedCoefficient, int128 maximizedExponent) = LibDecimalFloat.maximize(1, 0);
        assertEq(maximizedCoefficient, 1e38, "coefficient");
        assertEq(maximizedExponent, -38, "exponent");
    }

    /// 1e18 => 1e38
    function testMaximize1e18() external pure {
        (int128 maximizedCoefficient, int128 maximizedExponent) = LibDecimalFloat.maximize(1e18, 0);
        assertEq(maximizedCoefficient, 1e38, "coefficient");
        assertEq(maximizedExponent, -20, "exponent");
    }
}
