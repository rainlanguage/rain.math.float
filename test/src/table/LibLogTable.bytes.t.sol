// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {LibLogTable} from "src/lib/table/LibLogTable.sol";

contract LibLogTableBytesTest is Test {
    function testToBytesLogTableDec() external pure {
        bytes memory result = LibLogTable.toBytes(LibLogTable.logTableDec());
        console2.logBytes(result);
    }

    function testToBytesAntiLogTableDec() external pure {
        bytes memory result = LibLogTable.toBytes(LibLogTable.antiLogTableDec());
        console2.logBytes(result);
    }

    function testToBytesLogTableDecSmall() external pure {
        bytes memory result = LibLogTable.toBytes(LibLogTable.logTableDecSmall());
        console2.logBytes(result);
    }

    function testToBytesLogTableDecSmallAlt() external pure {
        bytes memory result = LibLogTable.toBytes(LibLogTable.logTableDecSmallAlt());
        console2.logBytes(result);
    }

    function testToBytesAntiLogTableDecSmall() external pure {
        bytes memory result = LibLogTable.toBytes(LibLogTable.antiLogTableDecSmall());
        console2.logBytes(result);
    }
}
