// SPDX-License-Identifier: CAL
pragma solidity ^0.8.25;

import {
    LOG_TABLES,
    LOG_TABLES_SMALL,
    LOG_TABLES_SMALL_ALT,
    ANTI_LOG_TABLES,
    ANTI_LOG_TABLES_SMALL
} from "../../generated/LogTables.pointers.sol";
import {LibDataContract, DataContractMemoryContainer} from "rain.datacontract/lib/LibDataContract.sol";
import {LibBytes} from "rain.solmem/lib/LibBytes.sol";
import {LibMemCpy, Pointer} from "rain.solmem/lib/LibMemCpy.sol";
import {DecimalFloat} from "../../concrete/DecimalFloat.sol";

address constant LOG_TABLES_ADDRESS = 0x7A0D94F55792C434d74a40883C6ed8545E406D12;

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

    function decimalFloatZoltu() internal returns (DecimalFloat deployedAddress) {
        bytes memory code = type(DecimalFloat).creationCode;
        bool success;
        assembly ("memory-safe") {
            mstore(0, 0)
            success := call(gas(), 0x7A0D94F55792C434d74a40883C6ed8545E406D12, 0, add(code, 0x20), mload(code), 12, 20)
            deployedAddress := mload(0)
        }
        if (!success) {
            revert("DecimalFloat: deploy failed");
        }
    }
}
