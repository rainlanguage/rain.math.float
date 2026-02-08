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
    /// Thrown when failing to ensure the DecimalFloat contract is deployed at
    /// the expected address or the codehash does not match the expected value.
    error DecimalFloatNotDeployed();

    address constant ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS = address(0xA43E75ee92c2949B95c8a79f427958cC0B05473e);

    bytes32 constant LOG_TABLES_DATA_CONTRACT_HASH = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;

    /// @dev Address of the DecimalFloat contract deployed via Zoltu's
    /// deterministic deployment proxy.
    /// This address is the same across all EVM-compatible networks.
    address constant ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS = address(0x12A66eFbE556e38308A17e34cC86f21DcA1CDB73);

    /// @dev The expected codehash of the DecimalFloat contract deployed via
    /// Zoltu's deterministic deployment proxy.
    bytes32 constant DECIMAL_FLOAT_CONTRACT_HASH = 0x705cdef2ed9538557152f86cd0988c748e0bd647a49df00b3e4f100c3544a583;

    function ensureDeployed() internal view {
        if (
            address(ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS).code.length == 0
                || address(ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS).codehash != DECIMAL_FLOAT_CONTRACT_HASH
        ) {
            revert DecimalFloatNotDeployed();
        }
    }

    /// Combines all log and anti-log tables into a single bytes array for
    /// deployment. These are using packed encoding to minimize size and remove
    /// the complexity of full ABI encoding.
    /// @return The combined tables.
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
}
