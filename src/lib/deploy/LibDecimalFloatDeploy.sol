// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
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
import {LOG_TABLE_DISAMBIGUATOR} from "../table/LibLogTable.sol";
import {WriteError} from "../../error/ErrDecimalFloat.sol";

/// @dev Zoltu deterministic deployment proxy address.
/// https://github.com/Zoltu/deterministic-deployment-proxy?tab=readme-ov-file#proxy-address
address constant ZOLTU_PROXY_ADDRESS = 0x7A0D94F55792C434d74a40883C6ed8545E406D12;

library LibDecimalFloatDeploy {
    function combinedTables() internal pure returns (bytes memory) {
        return abi.encodePacked(
            LOG_TABLES,
            LOG_TABLES_SMALL,
            LOG_TABLES_SMALL_ALT,
            ANTI_LOG_TABLES,
            ANTI_LOG_TABLES_SMALL,
            LOG_TABLE_DISAMBIGUATOR
        );
    }

    function dataContract() internal pure returns (DataContractMemoryContainer) {
        bytes memory tables = combinedTables();
        (DataContractMemoryContainer container, Pointer pointer) = LibDataContract.newContainer(tables.length);
        LibMemCpy.unsafeCopyBytesTo(LibBytes.dataPointer(tables), pointer, tables.length);
        return container;
    }

    function decimalFloatZoltu() internal returns (DecimalFloat deployedAddress) {
        //slither-disable-next-line too-many-digits
        bytes memory code = type(DecimalFloat).creationCode;
        bool success;
        address zoltuProxy = ZOLTU_PROXY_ADDRESS;
        assembly ("memory-safe") {
            mstore(0, 0)
            success := call(gas(), zoltuProxy, 0, add(code, 0x20), mload(code), 12, 20)
            deployedAddress := mload(0)
        }
        if (address(deployedAddress) == address(0) || !success) revert WriteError();
    }
}
