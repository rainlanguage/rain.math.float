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
import {LogTablesNotDeployed} from "../../error/ErrDecimalFloat.sol";

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
    address constant ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS = address(0x3963f256440e9D65D8a290eF1EfCA2d70C6EaeC9);

    /// @dev The expected codehash of the DecimalFloat contract deployed via
    /// Zoltu's deterministic deployment proxy.
    bytes32 constant DECIMAL_FLOAT_CONTRACT_HASH = 0x308dac13dccf56e44224b653a71f210bc20897d8f0f565ec2bae0ce5088c16de;

    /// @dev Deploy constants pinned to each version published to the soldeer
    /// registry. These are frozen literals — not aliases of the "current"
    /// constants above — so each keeps referencing its own release's deployment
    /// after the current constants advance to a newer version.
    /// `script/check-published-deploy-constants.sh` (run by
    /// `LibDecimalFloatDeployTaggedConstantsTest`) queries the registry and
    /// fails if any published version is missing its suite, so publishing a new
    /// tag forces pinning that tag's deploy constants here.

    /// @dev Log tables address at the published `0.1.1` soldeer tag.
    address constant ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS_0_1_1 = address(0xc51a14251b0dcF0ae24A96b7153991378938f5F5);

    /// @dev Log tables codehash at the published `0.1.1` soldeer tag.
    bytes32 constant LOG_TABLES_DATA_CONTRACT_HASH_0_1_1 =
        0x2573004ac3a9ee7fc8d73654d76386f1b6b99e34cdf86a689c4691e47143420f;

    /// @dev DecimalFloat address at the published `0.1.1` soldeer tag.
    address constant ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS_0_1_1 = address(0xBee0eEFaffD046c9602109eB30A858Be301CC926);

    /// @dev DecimalFloat codehash at the published `0.1.1` soldeer tag.
    bytes32 constant DECIMAL_FLOAT_CONTRACT_HASH_0_1_1 =
        0x7a93d0311f7782b44157ba40e94ec936085ebe001c7893bdd74911c8351d3def;

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

    /// Revert if the log tables data contract is not deployed at the
    /// Zoltu-deterministic address with the expected codehash. Call this
    /// from the constructor of any contract that integrates with the
    /// production `DecimalFloat` (or otherwise reads from
    /// `ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS`) so deployment fails loudly on
    /// chains where Zoltu has not dropped the tables, instead of silent
    /// `extcodecopy`-from-empty corruption at the first transcendental call.
    function checkLogTablesDeployed() internal view {
        bytes32 actualCodehash = ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS.codehash;
        if (actualCodehash != LOG_TABLES_DATA_CONTRACT_HASH) {
            revert LogTablesNotDeployed(
                ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS, LOG_TABLES_DATA_CONTRACT_HASH, actualCodehash
            );
        }
    }
}
