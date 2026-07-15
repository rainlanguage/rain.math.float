// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {LibCodeGen} from "rain-sol-codegen-0.1.0/src/lib/LibCodeGen.sol";
import {LibFs} from "rain-sol-codegen-0.1.0/src/lib/LibFs.sol";
import {LibDataContract} from "rain-datacontract-0.1.0/src/lib/LibDataContract.sol";
import {LibRainDeploy} from "rain-deploy-0.1.3/src/lib/LibRainDeploy.sol";
import {LibLogTable} from "../src/lib/table/LibLogTable.sol";
import {LibDecimalFloatDeploy} from "../src/lib/deploy/LibDecimalFloatDeploy.sol";
import {DecimalFloat} from "../src/concrete/DecimalFloat.sol";

contract BuildPointers is Script {
    function addressConstantString(string memory comment, string memory name, address addr)
        internal
        pure
        returns (string memory)
    {
        return string.concat("\n", comment, "\n", "address constant ", name, " = address(", vm.toString(addr), ");\n");
    }

    function bytes32ConstantString(string memory comment, string memory name, bytes32 value)
        internal
        pure
        returns (string memory)
    {
        return string.concat("\n", comment, "\n", "bytes32 constant ", name, " = ", vm.toString(value), ";\n");
    }

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

    /// @notice The deployment record for this release: the Zoltu-deterministic
    /// address and runtime codehash of BOTH deployables — the log-tables data
    /// contract and the `DecimalFloat` contract. Both addresses are a pure
    /// function of their creation code, so this is computed offline by deploying
    /// through a locally etched Zoltu factory. Frozen per release by
    /// `freezeSnapshot()`.
    function buildDeployPointers() internal {
        // The log tables must exist at their deterministic address before
        // DecimalFloat is deployed: its constructor calls
        // `checkLogTablesDeployed()`, which reads the codehash there.
        bytes memory logTablesCreationCode =
            LibDataContract.contractCreationCode(LibDecimalFloatDeploy.combinedTables());
        address logTables = LibRainDeploy.deployZoltu(logTablesCreationCode);

        address decimalFloat = LibRainDeploy.deployZoltu(type(DecimalFloat).creationCode);

        LibFs.buildFileForContract(
            vm,
            address(0),
            "DecimalFloatDeploy",
            string.concat(
                addressConstantString(
                    "/// @dev Address of the log tables data contract deployed via Zoltu's\n"
                    "/// deterministic deployment proxy. Identical across all EVM networks.",
                    "LOG_TABLES_DEPLOYED_ADDRESS",
                    logTables
                ),
                bytes32ConstantString(
                    "/// @dev Runtime codehash of the deployed log tables data contract.",
                    "LOG_TABLES_DEPLOYED_CODEHASH",
                    logTables.codehash
                ),
                addressConstantString(
                    "/// @dev Address of the DecimalFloat contract deployed via Zoltu's\n"
                    "/// deterministic deployment proxy. Identical across all EVM networks.",
                    "DECIMAL_FLOAT_DEPLOYED_ADDRESS",
                    decimalFloat
                ),
                bytes32ConstantString(
                    "/// @dev Runtime codehash of the deployed DecimalFloat contract.",
                    "DECIMAL_FLOAT_DEPLOYED_CODEHASH",
                    decimalFloat.codehash
                )
            )
        );
    }

    /// @notice The canonical release tag: `foundry.toml` `[package].version` with
    /// dots converted to underscores (`0.1.7` -> `0_1_7`) for the Solidity dir
    /// form — the single source of truth for the frozen-snapshot dir name.
    function deployTag() internal view returns (string memory) {
        string memory version = vm.parseTomlString(vm.readFile("foundry.toml"), ".package.version");
        bytes memory b = bytes(version);
        bytes memory out = new bytes(b.length);
        for (uint256 i = 0; i < b.length; i++) {
            out[i] = b[i] == "." ? bytes1("_") : b[i];
        }
        return string(out);
    }

    /// @notice Freeze the just-generated deploy pointers into a per-release
    /// snapshot dir `src/generated/<tag>/` so each published release keeps its
    /// own immutable deployment record. Only the CURRENT `deployTag()` dir is
    /// ever written — older tags are never touched. An existing `<tag>/`
    /// snapshot is treated as immutable: rewriting it with IDENTICAL content is
    /// a harmless no-op, but a DIFFERENT payload reverts. That only happens when
    /// the deployment changed without a `[package].version` bump — the change
    /// must bump the version so a NEW `<tag>/` dir is written beside the frozen
    /// ones, rather than corrupting the history consumers pin against.
    function freezeSnapshot() internal {
        string memory tag = deployTag();
        vm.createDir(string.concat("src/generated/", tag), true);
        string memory frozenPath = string.concat("src/generated/", tag, "/DecimalFloatDeploy.pointers.sol");
        string memory content = vm.readFile("src/generated/DecimalFloatDeploy.pointers.sol");
        if (vm.exists(frozenPath)) {
            require(
                keccak256(bytes(vm.readFile(frozenPath))) == keccak256(bytes(content)),
                "BuildPointers: frozen snapshot would change; bump [package].version for a new release"
            );
        }
        vm.writeFile(frozenPath, content);
    }

    function run() external {
        LibRainDeploy.etchZoltuFactory(vm);

        buildLogTablesData();
        buildDeployPointers();

        freezeSnapshot();
    }
}
