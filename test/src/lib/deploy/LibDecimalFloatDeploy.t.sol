// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.2/src/lib/LibRainDeploy.sol";
import {LibDecimalFloatDeploy} from "src/lib/deploy/LibDecimalFloatDeploy.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";
import {LibDataContract} from "rain-datacontract-0.1.0/src/lib/LibDataContract.sol";

/// @dev Pinned ETH L1 fork block. Forking at "latest" races RPC state
/// propagation: the node can advertise a freshly-finalized head before its
/// state is queryable, causing flakes. The CI `CI_FORK_ETH_RPC_URL` is a
/// non-archive node that prunes state past a recent retention window, so
/// the pin must stay near the head — older blocks fail with "state at
/// block #N is pruned". This block is the head as of pinning; bump
/// periodically as state ages out.
uint256 constant FORK_BLOCK_NUMBER = 25055000;

contract LibDecimalFloatDeployTest is Test {
    function testDeployAddress() external {
        vm.createSelectFork(vm.envString("CI_FORK_ETH_RPC_URL"), FORK_BLOCK_NUMBER);
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
        vm.createSelectFork(vm.envString("CI_FORK_ETH_RPC_URL"), FORK_BLOCK_NUMBER);
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
