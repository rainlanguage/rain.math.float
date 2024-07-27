// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Script} from "forge-std/Script.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");

        DataContractMemoryContainer memory container = LibDecimalFloatDeploy.dataContract();

        vm.startBroadcast(deployerPrivateKey);

        containter.write();

        vm.stopBroadcast();
    }
}
