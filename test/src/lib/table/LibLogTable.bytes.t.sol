// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibLogTable} from "src/lib/table/LibLogTable.sol";
import {
    LOG_TABLES,
    LOG_TABLES_SMALL,
    LOG_TABLES_SMALL_ALT,
    ANTI_LOG_TABLES,
    ANTI_LOG_TABLES_SMALL
} from "src/generated/LogTables.pointers.sol";

/// @title LibLogTableBytesTest
/// @notice Verifies that toBytes encoding of each table matches the
/// AOT-compiled constants in LogTables.pointers.sol.
contract LibLogTableBytesTest is Test {
    /// toBytes(logTableDec()) matches the generated LOG_TABLES constant.
    function testToBytesLogTableDec() external pure {
        bytes memory result = LibLogTable.toBytes(LibLogTable.logTableDec());
        assertEq(result, LOG_TABLES, "log table encoding mismatch");
    }

    /// toBytes(antiLogTableDec()) matches the generated ANTI_LOG_TABLES constant.
    function testToBytesAntiLogTableDec() external pure {
        bytes memory result = LibLogTable.toBytes(LibLogTable.antiLogTableDec());
        assertEq(result, ANTI_LOG_TABLES, "antilog table encoding mismatch");
    }

    /// toBytes(logTableDecSmall()) matches the generated LOG_TABLES_SMALL constant.
    function testToBytesLogTableDecSmall() external pure {
        bytes memory result = LibLogTable.toBytes(LibLogTable.logTableDecSmall());
        assertEq(result, LOG_TABLES_SMALL, "log small table encoding mismatch");
    }

    /// toBytes(logTableDecSmallAlt()) matches the generated LOG_TABLES_SMALL_ALT constant.
    function testToBytesLogTableDecSmallAlt() external pure {
        bytes memory result = LibLogTable.toBytes(LibLogTable.logTableDecSmallAlt());
        assertEq(result, LOG_TABLES_SMALL_ALT, "log small alt table encoding mismatch");
    }

    /// toBytes(antiLogTableDecSmall()) matches the generated ANTI_LOG_TABLES_SMALL constant.
    function testToBytesAntiLogTableDecSmall() external pure {
        bytes memory result = LibLogTable.toBytes(LibLogTable.antiLogTableDecSmall());
        assertEq(result, ANTI_LOG_TABLES_SMALL, "antilog small table encoding mismatch");
    }
}
