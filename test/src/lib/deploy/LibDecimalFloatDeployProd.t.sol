// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibDecimalFloatDeploy} from "src/lib/deploy/LibDecimalFloatDeploy.sol";
import {LibRainDeploy} from "rain.deploy/lib/LibRainDeploy.sol";

/// @title LibDecimalFloatDeployProdTest
/// @notice Verifies that both the log tables data contract and the DecimalFloat
/// contract are deployed on every supported production network with the expected
/// addresses and code hashes.
contract LibDecimalFloatDeployProdTest is Test {
    function checkProdDeployment(string memory network) internal {
        vm.createSelectFork(network);

        address logTables = LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS;
        assertTrue(logTables.code.length > 0, string.concat(network, ": log tables not deployed"));
        assertEq(
            logTables.codehash,
            LibDecimalFloatDeploy.LOG_TABLES_DATA_CONTRACT_HASH,
            string.concat(network, ": log tables code hash mismatch")
        );

        address decimalFloat = LibDecimalFloatDeploy.ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS;
        assertTrue(decimalFloat.code.length > 0, string.concat(network, ": DecimalFloat not deployed"));
        assertEq(
            decimalFloat.codehash,
            LibDecimalFloatDeploy.DECIMAL_FLOAT_CONTRACT_HASH,
            string.concat(network, ": DecimalFloat code hash mismatch")
        );
    }

    function testProdDeploymentArbitrum() external {
        checkProdDeployment("arbitrum");
    }

    function testProdDeploymentBase() external {
        checkProdDeployment("base");
    }

    function testProdDeploymentBaseSepolia() external {
        checkProdDeployment("base_sepolia");
    }

    function testProdDeploymentFlare() external {
        checkProdDeployment("flare");
    }

    function testProdDeploymentPolygon() external {
        checkProdDeployment("polygon");
    }
}
