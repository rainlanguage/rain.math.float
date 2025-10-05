// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std/Script.sol";
import {DataContractMemoryContainer, LibDataContract} from "rain.datacontract/lib/LibDataContract.sol";
import {LibDecimalFloatDeploy} from "../src/lib/deploy/LibDecimalFloatDeploy.sol";

contract Deploy is Script {
    using LibDataContract for DataContractMemoryContainer;

    function deployDataContract(DataContractMemoryContainer container) internal {
        container.writeZoltu();
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");

        DataContractMemoryContainer container = LibDecimalFloatDeploy.dataContract();

        vm.startBroadcast(deployerPrivateKey);

        deployDataContract(container);

        // LibDecimalFloatDeploy.decimalFloatZoltu();

        vm.stopBroadcast();
    }
}
