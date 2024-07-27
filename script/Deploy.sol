// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Script} from "forge-std/Script.sol";
import {DataContractMemoryContainer, LibDataContract} from "rain.datacontract/lib/LibDataContract.sol";
import {LibDecimalFloatDeploy} from "../src/lib/LibDecimalFloatDeploy.sol";

contract Deploy is Script {
    using LibDataContract for DataContractMemoryContainer;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");

        DataContractMemoryContainer container = LibDecimalFloatDeploy.dataContract();

        vm.startBroadcast(deployerPrivateKey);

        container.write();

        vm.stopBroadcast();
    }
}
