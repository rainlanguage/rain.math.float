// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {DecimalFloat, LibDecimalFloat} from "src/DecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract DecimalFloatExp2Test is Test {
    // function testExp2Gas(int128 x) external pure {
    //     x = int128(bound(x, type(int128).min, 0x400000000000000000 - 1));
    //     LibDecimalFloat.exp_2(x);
    // }

    // function testExp22Gas(int128 x) external pure {
    //     x = int128(bound(x, type(int128).min, 0x400000000000000000 - 1));
    //     LibDecimalFloat.exp22(x);
    // }

    // function testExp2GasZero() external pure {
    //     LibDecimalFloat.exp_2(0);
    // }

    // function testExp22GasZero() external pure {
    //     LibDecimalFloat.exp22(0);
    // }

    // function testExp2GasMax() external pure {
    //     LibDecimalFloat.exp_2(0x400000000000000000 - 1);
    // }

    // function testExp22GasMax() external pure {
    //     LibDecimalFloat.exp22(0x400000000000000000 - 1);
    // }

    // function testExp2Compare(int128 x) external pure {
    //     x = int128(bound(x, 0, 0x400000000000000000 - 1));
    //     assertEq(LibDecimalFloat.exp_2(x), LibDecimalFloat.exp22(x));
    // }

    // function testExp2Zero() external pure {
    //     assertEq(LibDecimalFloat.exp_2(0), 18446744073709551616);
    // }

    // function testExp22Zero() external pure {
    //     assertEq(LibDecimalFloat.exp22(0), 18446744073709551616);
    // }
}
