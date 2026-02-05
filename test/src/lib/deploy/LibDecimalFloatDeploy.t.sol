// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {LibDecimalFloatDeploy, DecimalFloat} from "src/lib/deploy/LibDecimalFloatDeploy.sol";

contract LibDecimalFloatDeployTest is Test {
    function testDecimalFloatZoltu() external {
        vm.createSelectFork(vm.envString("CI_FORK_ETH_RPC_URL"));

        DecimalFloat deployedZoltu = LibDecimalFloatDeploy.decimalFloatZoltu();
        assertTrue(address(deployedZoltu) != address(0));

        DecimalFloat deployedDirect = new DecimalFloat();

        assertEq(address(deployedZoltu).codehash, address(deployedDirect).codehash);
    }

    function testDecimalFloatZoltuProd() external {
        string[] memory forkRpcUrls = new string[](3);
        forkRpcUrls[0] = "CI_FORK_FLARE_RPC_URL";
        forkRpcUrls[1] = "CI_FORK_BASE_RPC_URL";
        forkRpcUrls[2] = "CI_FORK_ARB_RPC_URL";

        for (uint256 i = 0; i < forkRpcUrls.length; i++) {
            console2.log("Testing fork:", forkRpcUrls[i]);
            vm.createSelectFork(vm.envString(forkRpcUrls[i]));

            assertEq(
                LibDecimalFloatDeploy.DECIMAL_FLOAT_DATA_CONTRACT_HASH,
                LibDecimalFloatDeploy.ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS.codehash,
                forkRpcUrls[i]
            );
        }
    }
}
