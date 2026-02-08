// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibRainDeploy} from "rain.deploy/lib/LibRainDeploy.sol";
import {LibDecimalFloatDeploy, DecimalFloat} from "src/lib/deploy/LibDecimalFloatDeploy.sol";
import {LibDataContract} from "rain.datacontract/lib/LibDataContract.sol";

contract LibDecimalFloatDeployTest is Test {
    function testDeployAddress() external {
        vm.createSelectFork(vm.envString("CI_FORK_ETH_RPC_URL"));
        address deployedAddress = LibRainDeploy.deployZoltu(type(DecimalFloat).creationCode);

        assertEq(deployedAddress, LibDecimalFloatDeploy.ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS);
        assertTrue(address(deployedAddress).code.length > 0, "Deployed address has no code");

        assertEq(address(deployedAddress).codehash, LibDecimalFloatDeploy.DECIMAL_FLOAT_CONTRACT_HASH);
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
        assertTrue(address(deployedAddress).code.length > 0, "Deployed address has no code");
    }
}
