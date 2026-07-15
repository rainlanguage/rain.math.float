// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {LibCodeGen} from "rain-sol-codegen-0.1.2/src/lib/LibCodeGen.sol";
import {LibFs} from "rain-sol-codegen-0.1.2/src/lib/LibFs.sol";
import {LibSnapshot} from "rain-sol-codegen-0.1.2/src/lib/LibSnapshot.sol";
import {LibDataContract} from "rain-datacontract-0.1.0/src/lib/LibDataContract.sol";
import {LibRainDeploy} from "rain-deploy-0.1.3/src/lib/LibRainDeploy.sol";
import {LibLogTable} from "../src/lib/table/LibLogTable.sol";
import {LibDecimalFloatDeploy} from "../src/lib/deploy/LibDecimalFloatDeploy.sol";
import {DecimalFloat} from "../src/concrete/DecimalFloat.sol";

contract BuildPointers is Script {
    /// @notice The log/antilog lookup table data consumed by
    /// `LibDecimalFloatDeploy.combinedTables()`. This is source data, not a
    /// deployment record, so it is not part of the per-release snapshot.
    function buildLogTablesData() internal {
        LibFs.buildFileForContract(
            vm,
            address(0),
            "LogTables",
            string.concat(
                LibCodeGen.bytesConstantString(
                    vm, "/// @dev Log tables.", "LOG_TABLES", LibLogTable.toBytes(LibLogTable.logTableDec())
                ),
                LibCodeGen.bytesConstantString(
                    vm,
                    "/// @dev Log tables small.",
                    "LOG_TABLES_SMALL",
                    LibLogTable.toBytes(LibLogTable.logTableDecSmall())
                ),
                LibCodeGen.bytesConstantString(
                    vm,
                    "/// @dev Log tables small alt.",
                    "LOG_TABLES_SMALL_ALT",
                    LibLogTable.toBytes(LibLogTable.logTableDecSmallAlt())
                ),
                LibCodeGen.bytesConstantString(
                    vm,
                    "/// @dev Anti log tables.",
                    "ANTI_LOG_TABLES",
                    LibLogTable.toBytes(LibLogTable.antiLogTableDec())
                ),
                LibCodeGen.bytesConstantString(
                    vm,
                    "/// @dev Anti log tables small.",
                    "ANTI_LOG_TABLES_SMALL",
                    LibLogTable.toBytes(LibLogTable.antiLogTableDecSmall())
                )
            )
        );
    }

    /// @notice The deployment record for one deployable: its Zoltu-deterministic
    /// address, the creation bytecode it is deployed FROM, and the runtime
    /// bytecode it is verified AGAINST on-chain. `LibFs` prepends `BYTECODE_HASH`
    /// derived from the passed instance, so the record is complete — address +
    /// codehash + creation + runtime. A pin carrying only address + codehash
    /// cannot reproduce or independently verify a past release.
    ///
    /// One file PER contract: `BYTECODE_HASH` identifies a single instance, so
    /// combining two deployables into one file would leave it meaningless.
    function buildDeployPointersFor(string memory contractName, bytes memory creationCode, address deployed) internal {
        LibFs.buildFileForContract(
            vm,
            deployed,
            contractName,
            string.concat(
                LibCodeGen.addressConstantString(
                    vm,
                    "/// @dev Address of the contract deployed via Zoltu's deterministic\n"
                    "/// deployment proxy. Identical across all EVM-compatible networks.",
                    "DEPLOYED_ADDRESS",
                    deployed
                ),
                LibCodeGen.bytesConstantString(
                    vm, "/// @dev The creation bytecode of the contract.", "CREATION_CODE", creationCode
                ),
                LibCodeGen.bytesConstantString(
                    vm, "/// @dev The runtime bytecode of the contract.", "RUNTIME_CODE", deployed.code
                )
            )
        );
    }

    /// @notice This release's deployment record: both deployables, each in its
    /// own pointers file. Every address is a pure function of its creation code
    /// (Zoltu CREATE2), so the whole record is computed offline through a locally
    /// etched factory. Frozen per release by `LibSnapshot`.
    function buildDeployPointers() internal {
        // The log tables must land first: DecimalFloat's constructor calls
        // `checkLogTablesDeployed()`, which reads the codehash at their address.
        bytes memory logTablesCreationCode =
            LibDataContract.contractCreationCode(LibDecimalFloatDeploy.combinedTables());
        buildDeployPointersFor(
            "LogTablesDeploy", logTablesCreationCode, LibRainDeploy.deployZoltu(logTablesCreationCode)
        );

        bytes memory decimalFloatCreationCode = type(DecimalFloat).creationCode;
        buildDeployPointersFor(
            "DecimalFloatDeploy", decimalFloatCreationCode, LibRainDeploy.deployZoltu(decimalFloatCreationCode)
        );
    }

    /// @notice The generated files that make up this release's deployment
    /// record, frozen per release tag by `LibSnapshot`. The log-tables DATA is
    /// deliberately absent: it is source input, not a deployment record.
    function snapshotContractNames() internal pure returns (string[] memory names) {
        names = new string[](2);
        names[0] = "LogTablesDeploy";
        names[1] = "DecimalFloatDeploy";
    }

    function run() external {
        LibRainDeploy.etchZoltuFactory(vm);

        buildLogTablesData();
        buildDeployPointers();

        // Freeze this release's record into `src/generated/<tag>/`. The tag, the
        // freeze and the guard that refuses to rewrite a frozen record without a
        // `[package].version` bump all live in the shared `LibSnapshot` — this
        // repo does not carry its own copy.
        LibSnapshot.freezeSnapshot(vm, snapshotContractNames());
    }
}
