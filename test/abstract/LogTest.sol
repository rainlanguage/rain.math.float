// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

// Re-export console2 here for convenience.
// forge-lint: disable-next-line(unused-import)
import {Test, console2} from "forge-std-1.16.1/src/Test.sol";
import {LibDataContract} from "rain-datacontract-0.1.3/src/lib/LibDataContract.sol";
import {LibLogTable, LOG_TABLE_DISAMBIGUATOR} from "src/lib/table/LibLogTable.sol";

abstract contract LogTest is Test {
    address sTables;

    /// Deploy the combined log/anti-log tables data contract at a `create`
    /// address and return it, rebuilding the table bytes purely from
    /// `LibLogTable` source. The transcendental library functions take the
    /// tables-contract address as a parameter, so this self-contained helper is
    /// all the pure-math suite needs: no Zoltu-deterministic deploy pin, no
    /// frozen `src/generated` snapshot.
    function logTables() internal returns (address) {
        if (sTables == address(0)) {
            bytes memory tables = abi.encodePacked(
                LibLogTable.toBytes(LibLogTable.logTableDec()),
                LibLogTable.toBytes(LibLogTable.logTableDecSmall()),
                LibLogTable.toBytes(LibLogTable.logTableDecSmallAlt()),
                LibLogTable.toBytes(LibLogTable.antiLogTableDec()),
                LibLogTable.toBytes(LibLogTable.antiLogTableDecSmall()),
                LOG_TABLE_DISAMBIGUATOR
            );
            bytes memory creationCode = LibDataContract.contractCreationCode(tables);
            address tablesAddress;
            assembly ("memory-safe") {
                tablesAddress := create(0, add(creationCode, 0x20), mload(creationCode))
            }
            assertTrue(tablesAddress != address(0), "Failed to deploy tables");
            sTables = tablesAddress;
        }
        return sTables;
    }
}
