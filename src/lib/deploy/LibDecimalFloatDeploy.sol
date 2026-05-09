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
import {LOG_TABLE_DISAMBIGUATOR} from "../table/LibLogTable.sol";

library LibDecimalFloatDeploy {
    /// @dev Address of the log tables deployed via Zoltu's deterministic
    /// deployment proxy. This address is the same across all EVM-compatible
    /// networks.
    address constant ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS = address(0xc51a14251b0dcF0ae24A96b7153991378938f5F5);

    /// @dev The expected codehash of the log tables deployed via Zoltu's
    /// deterministic deployment proxy.
    bytes32 constant LOG_TABLES_DATA_CONTRACT_HASH = 0x2573004ac3a9ee7fc8d73654d76386f1b6b99e34cdf86a689c4691e47143420f;

    /// @dev Address of the DecimalFloat contract deployed via Zoltu's
    /// deterministic deployment proxy.
    /// This address is the same across all EVM-compatible networks.
    address constant ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS = address(0xf37226d8e35de6091e95E38ca87D24Ec537BA5Ea);

    /// @dev The expected codehash of the DecimalFloat contract deployed via
    /// Zoltu's deterministic deployment proxy.
    bytes32 constant DECIMAL_FLOAT_CONTRACT_HASH = 0x694f5f6992725624d7081268ab6e0cec5a7fe02a1a75deb621a65898eb1d7437;

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
