// SPDX-License-Identifier: CAL
pragma solidity ^0.8.25;

import {
    LOG_TABLES,
    LOG_TABLES_SMALL,
    LOG_TABLES_SMALL_ALT,
    ANTI_LOG_TABLES,
    ANTI_LOG_TABLES_SMALL
} from "../generated/LogTables.pointers.sol";
import {LibDataContract, DataContractMemoryContainer} from "rain.datacontract/lib/LibDataContract.sol";
import {LibBytes} from "rain.solmem/lib/LibBytes.sol";
import {LibMemCpy, Pointer} from "rain.solmem/lib/LibMemCpy.sol";

library LibDecimalFloatDeploy {
    function combinedTables() internal pure returns (bytes memory) {
        return
            abi.encodePacked(LOG_TABLES, LOG_TABLES_SMALL, LOG_TABLES_SMALL_ALT, ANTI_LOG_TABLES, ANTI_LOG_TABLES_SMALL);
    }

    function dataContract() internal pure returns (DataContractMemoryContainer) {
        bytes memory tables = combinedTables();
        (DataContractMemoryContainer container, Pointer pointer) = LibDataContract.newContainer(tables.length);
        LibMemCpy.unsafeCopyBytesTo(LibBytes.dataPointer(tables), pointer, tables.length);
        return container;
    }
}
