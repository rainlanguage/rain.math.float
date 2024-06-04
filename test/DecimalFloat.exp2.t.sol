// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {DecimalFloat, LibDecimalFloat} from "src/DecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract DecimalFloatExp2Test is Test {
    function testExp2Gas(int128 x) external pure {
        x = int128(bound(x, type(int128).min, 0x400000000000000000 - 1));
        LibDecimalFloat.exp_2(x);
    }

    function testExp2Compare(int128 x) external pure {
        x = int128(bound(x, type(int128).min, 0x400000000000000000 - 1));
        assertEq(LibDecimalFloat.exp_2(x), LibDecimalFloat.exp22(x));
    }
}
