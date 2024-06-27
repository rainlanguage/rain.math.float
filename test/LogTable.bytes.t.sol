// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {LibLogTable} from "src/LibLogTable.sol";

contract LibLogTableBytesTest is Test {
    function testToBytesLogTableDec() external {
        bytes memory result = LibLogTable.toBytes(LibLogTable.logTableDec());
        console2.logBytes(result);
    }

    function testToBytesAntiLogTableDec() external {
        bytes memory result = LibLogTable.toBytes(LibLogTable.antiLogTableDec());
        console2.logBytes(result);
    }

    function testToBytesLogTableDecSmall() external {
        bytes memory result = LibLogTable.toBytes(LibLogTable.logTableDecSmall());
        console2.logBytes(result);
    }

    function testToBytesLogTableDecSmallAlt() external {
        bytes memory result = LibLogTable.toBytes(LibLogTable.logTableDecSmallAlt());
        console2.logBytes(result);
    }

    function testToBytesAntiLogTableDecSmall() external {
        bytes memory result = LibLogTable.toBytes(LibLogTable.antiLogTableDecSmall());
        console2.logBytes(result);
    }
}
