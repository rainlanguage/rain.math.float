// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {LibLogTable} from "src/LogTable.sol";

contract LibLogTableBytesTest is Test {
    function testToBytesLogTableDec() external {
        bytes memory result = LibLogTable.toBytes(LibLogTable.logTableDec());
        console2.logBytes(result);
    }

    function testToBytesAntiLogTableDec() external {
        bytes memory result = LibLogTable.toBytes(LibLogTable.antiLogTableDec());
        console2.logBytes(result);
    }
}
