// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDataContract} from "rain-datacontract-0.2.0/src/lib/LibDataContract.sol";
import {LibLogTable, LOG_TABLE_DISAMBIGUATOR} from "src/lib/table/LibLogTable.sol";

error LogTablesNotDeployed();

library LibTestLogTables {
    /// Deploys the combined log tables from `LibLogTable` source as a data
    /// contract at a `create` address and returns it.
    function deploy() internal returns (address) {
        return deploy(LibLogTable.logTableDecSmall(), LibLogTable.logTableDecSmallAlt());
    }

    /// As `deploy`, with the given small log tables in place of the source
    /// ones.
    function deploy(uint8[10][90] memory logSmall, uint8[10][10] memory logSmallAlt) internal returns (address) {
        bytes memory tables = abi.encodePacked(
            LibLogTable.toBytes(LibLogTable.logTableDec()),
            LibLogTable.toBytes(logSmall),
            LibLogTable.toBytes(logSmallAlt),
            LibLogTable.toBytes(LibLogTable.antiLogTableDec()),
            LibLogTable.toBytes(LibLogTable.antiLogTableDecSmall()),
            LOG_TABLE_DISAMBIGUATOR
        );
        bytes memory creationCode = LibDataContract.contractCreationCode(tables);
        address tablesAddress;
        assembly ("memory-safe") {
            tablesAddress := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        if (tablesAddress == address(0)) {
            revert LogTablesNotDeployed();
        }
        return tablesAddress;
    }
}
