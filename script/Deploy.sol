// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std/Script.sol";
import {DataContractMemoryContainer, LibDataContract} from "rain.datacontract/lib/LibDataContract.sol";
import {LibDecimalFloatDeploy} from "../src/lib/deploy/LibDecimalFloatDeploy.sol";

bytes32 constant DEPLOYMENT_SUITE_ALL = keccak256("all");
bytes32 constant DEPLOYMENT_SUITE_TABLES = keccak256("deployment.suite.tables");
bytes32 constant DEPLOYMENT_SUITE_CONTRACT = keccak256("deployment.suite.contract");

contract Deploy is Script {
    using LibDataContract for DataContractMemoryContainer;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");
        string memory suiteString = vm.envOr("DEPLOYMENT_SUITE", string("all"));
        bytes32 suite = keccak256(bytes(suiteString));

        DataContractMemoryContainer container = LibDecimalFloatDeploy.dataContract();

        vm.startBroadcast(deployerPrivateKey);

        if (suite == DEPLOYMENT_SUITE_ALL || suite == DEPLOYMENT_SUITE_TABLES) {
            container.writeZoltu();
        }

        if (suite == DEPLOYMENT_SUITE_ALL || suite == DEPLOYMENT_SUITE_CONTRACT) {
            LibDecimalFloatDeploy.decimalFloatZoltu();
        }

        vm.stopBroadcast();
    }
}
