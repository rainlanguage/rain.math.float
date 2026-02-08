// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std/Script.sol";
import {DataContractMemoryContainer, LibDataContract} from "rain.datacontract/lib/LibDataContract.sol";
import {LibDecimalFloatDeploy} from "../src/lib/deploy/LibDecimalFloatDeploy.sol";
import {LibRainDeploy} from "rain.deploy/lib/LibRainDeploy.sol";
import {DecimalFloat} from "../src/concrete/DecimalFloat.sol";

bytes32 constant DEPLOYMENT_SUITE_ALL = keccak256("all");
bytes32 constant DEPLOYMENT_SUITE_TABLES = keccak256("deployment.suite.tables");
bytes32 constant DEPLOYMENT_SUITE_CONTRACT = keccak256("deployment.suite.contract");

contract Deploy is Script {
    using LibDataContract for DataContractMemoryContainer;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");

        if (
            LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS.code.length == 0
                || LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS.codehash
                    != LibDecimalFloatDeploy.LOG_TABLES_DATA_CONTRACT_HASH
        ) {
            console2.log("Log tables not deployed, deploying now...");
            LibRainDeploy.deployAndBroadcastToSupportedNetworks(
                vm,
                LibRainDeploy.supportedNetworks(),
                deployerPrivateKey,
                LibDataContract.contractCreationCode(LibDecimalFloatDeploy.combinedTables()),
                "",
                LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS,
                LibDecimalFloatDeploy.LOG_TABLES_DATA_CONTRACT_HASH,
                new address[](0)
            );

            console2.log("Log tables deployed successfully.");
            console2.log(
                "Please reun the deployment script to deploy the DecimalFloat contract now that the dependency is in place."
            );
        } else {
            address[] memory decimalFloatDependencies = new address[](1);
            decimalFloatDependencies[0] = LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS;
            LibRainDeploy.deployAndBroadcastToSupportedNetworks(
                vm,
                LibRainDeploy.supportedNetworks(),
                deployerPrivateKey,
                type(DecimalFloat).creationCode,
                "src/concrete/DecimalFloat.sol:DecimalFloat",
                LibDecimalFloatDeploy.ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS,
                LibDecimalFloatDeploy.DECIMAL_FLOAT_CONTRACT_HASH,
                decimalFloatDependencies
            );
        }

        // string memory suiteString = vm.envOr("DEPLOYMENT_SUITE", string("all"));
        // bytes32 suite = keccak256(bytes(suiteString));

        // DataContractMemoryContainer container = LibDecimalFloatDeploy.dataContract();

        // vm.startBroadcast(deployerPrivateKey);

        // if (suite == DEPLOYMENT_SUITE_ALL || suite == DEPLOYMENT_SUITE_TABLES) {
        //     container.writeZoltu();
        // }

        // if (suite == DEPLOYMENT_SUITE_ALL || suite == DEPLOYMENT_SUITE_CONTRACT) {
        //     LibDecimalFloatDeploy.decimalFloatZoltu();
        // }

        // vm.stopBroadcast();
    }
}
