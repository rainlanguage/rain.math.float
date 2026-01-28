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

library LibDecimalFloatDeploy {
    /// @dev Zoltu deterministic deployment proxy address.
    /// https://github.com/Zoltu/deterministic-deployment-proxy?tab=readme-ov-file#proxy-address
    address constant ZOLTU_PROXY_ADDRESS = 0x7A0D94F55792C434d74a40883C6ed8545E406D12;

    /// @dev Address of the DecimalFloat contract deployed via Zoltu's
    /// deterministic deployment proxy.
    /// This address is the same across all EVM-compatible networks.
    address constant ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS = address(0x6421E8a23cdEe2E6E579b2cDebc8C2A514843593);

    /// @dev The expected codehash of the DecimalFloat contract deployed via
    /// Zoltu's deterministic deployment proxy.
    bytes32 constant DECIMAL_FLOAT_DATA_CONTRACT_HASH =
        0x2573004ac3a9ee7fc8d73654d76386f1b6b99e34cdf86a689c4691e47143420f;

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

    /// Deploys a DecimalFloat contract using Zoltu's deterministic deployment
    /// proxy contract. This allows the concrete DecimalFloat contract to be
    /// found at a predictable location regardless of the network.
    /// Reverts with WriteError if deployment fails.
    /// @return deployedAddress The address of the deployed DecimalFloat
    /// contract.
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
