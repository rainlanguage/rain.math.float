// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.16.1/src/Vm.sol";
import {LibDataContract} from "rain-datacontract-0.1.0/src/lib/LibDataContract.sol";
import {LibDecimalFloatDeploy} from "src/lib/deploy/LibDecimalFloatDeploy.sol";

/// @notice Shared logic for planting the log-tables data contract at its
/// Zoltu-deterministic address inside a forge VM. Used by `script/Deploy.sol`
/// (so the decimal-float simulation pass can pass the constructor's codehash
/// check before log-tables exists on-chain) and by tests that need
/// `DecimalFloat` operations to work without a real on-chain deploy.
library LibEtchLogTables {
    /// @notice Deploys the log-tables data contract to a temporary address,
    /// copies its runtime code, and etches that runtime at
    /// `LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS` so the
    /// codehash matches `LibDecimalFloatDeploy.LOG_TABLES_DATA_CONTRACT_HASH`.
    function etchLogTables(Vm vm) internal {
        bytes memory tables = LibDecimalFloatDeploy.combinedTables();
        bytes memory creationCode = LibDataContract.contractCreationCode(tables);
        address temp;
        assembly ("memory-safe") {
            temp := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        require(temp != address(0), "log tables etch deploy failed");
        vm.etch(LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS, temp.code);
    }
}
