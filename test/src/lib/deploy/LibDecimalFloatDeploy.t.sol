// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {LibRainDeploy} from "rain.deploy/lib/LibRainDeploy.sol";
import {LibDecimalFloatDeploy, DecimalFloat} from "src/lib/deploy/LibDecimalFloatDeploy.sol";
import {LibDataContract} from "rain.datacontract/lib/LibDataContract.sol";

contract LibDecimalFloatDeployTest is Test {
    function testDeployAddress() external {
        vm.createSelectFork(vm.envString("CI_FORK_ETH_RPC_URL"));
        address deployedAddress = LibRainDeploy.deployZoltu(type(DecimalFloat).creationCode);
        assertEq(deployedAddress, LibDecimalFloatDeploy.ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS);

        LibDecimalFloatDeploy.ensureDeployed();
    }

    function testExpectedCodeHashDecimalFloat() external {
        DecimalFloat decimalFloat = new DecimalFloat();

        assertEq(address(decimalFloat).codehash, LibDecimalFloatDeploy.DECIMAL_FLOAT_CONTRACT_HASH);
    }

    function testDeployAddressLogTables() external {
        vm.createSelectFork(vm.envString("CI_FORK_ETH_RPC_URL"));
        bytes memory logTables = LibDataContract.contractCreationCode(LibDecimalFloatDeploy.combinedTables());

        address deployedAddress = LibRainDeploy.deployZoltu(logTables);

        assertEq(deployedAddress, LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS);

        assertEq(address(deployedAddress).codehash, LibDecimalFloatDeploy.LOG_TABLES_DATA_CONTRACT_HASH);
    }

    function testExpectedCodeHashLogTables() external {
        bytes memory logTables = LibDataContract.contractCreationCode(LibDecimalFloatDeploy.combinedTables());

        address deployedAddress;
        assembly ("memory-safe") {
            deployedAddress := create(0, add(logTables, 0x20), mload(logTables))
        }

        assertEq(deployedAddress.codehash, LibDecimalFloatDeploy.LOG_TABLES_DATA_CONTRACT_HASH);
    }

    // function testDecimalFloatZoltu() external {
    //     vm.createSelectFork(vm.envString("CI_FORK_ETH_RPC_URL"));

    //     DecimalFloat deployedZoltu = LibDecimalFloatDeploy.decimalFloatZoltu();
    //     assertTrue(address(deployedZoltu) != address(0));

    //     DecimalFloat deployedDirect = new DecimalFloat();

    //     assertEq(address(deployedZoltu).codehash, address(deployedDirect).codehash);
    // }

    // function testDecimalFloatZoltuProd() external {
    //     string[] memory forkRpcUrls = new string[](3);
    //     forkRpcUrls[0] = "CI_FORK_FLARE_RPC_URL";
    //     forkRpcUrls[1] = "CI_FORK_BASE_RPC_URL";
    //     forkRpcUrls[2] = "CI_FORK_ARB_RPC_URL";

    //     for (uint256 i = 0; i < forkRpcUrls.length; i++) {
    //         console2.log("Testing fork:", forkRpcUrls[i]);
    //         vm.createSelectFork(vm.envString(forkRpcUrls[i]));

    //         assertEq(
    //             LibDecimalFloatDeploy.DECIMAL_FLOAT_DATA_CONTRACT_HASH,
    //             LibDecimalFloatDeploy.ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS.codehash,
    //             forkRpcUrls[i]
    //         );
    //     }
    // }
}
