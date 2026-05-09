// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibDecimalFloatDeploy} from "src/lib/deploy/LibDecimalFloatDeploy.sol";
import {LibDataContract} from "rain.datacontract/lib/LibDataContract.sol";
import {LogTablesNotDeployed} from "src/error/ErrDecimalFloat.sol";

/// Direct tests for `LibDecimalFloatDeploy.checkLogTablesDeployed`. These
/// deliberately do NOT inherit `LogTest` so the table address starts empty.
contract LibDecimalFloatDeployCheckLogTablesDeployedTest is Test {
    /// Empty address → revert with the expected error and arguments.
    function testCheckLogTablesDeployedRevertsWhenMissing() external {
        bytes32 actualCodehash = LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS.codehash;
        vm.expectRevert(
            abi.encodeWithSelector(
                LogTablesNotDeployed.selector,
                LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS,
                LibDecimalFloatDeploy.LOG_TABLES_DATA_CONTRACT_HASH,
                actualCodehash
            )
        );
        this.callCheckLogTablesDeployed();
    }

    /// Wrong bytecode at the address → codehash mismatch → revert.
    function testCheckLogTablesDeployedRevertsOnWrongCodehash() external {
        bytes memory junk = hex"deadbeef";
        vm.etch(LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS, junk);
        bytes32 actualCodehash = LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS.codehash;
        assertTrue(actualCodehash != LibDecimalFloatDeploy.LOG_TABLES_DATA_CONTRACT_HASH);
        vm.expectRevert(
            abi.encodeWithSelector(
                LogTablesNotDeployed.selector,
                LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS,
                LibDecimalFloatDeploy.LOG_TABLES_DATA_CONTRACT_HASH,
                actualCodehash
            )
        );
        this.callCheckLogTablesDeployed();
    }

    /// Correct table runtime at the expected address → no revert.
    function testCheckLogTablesDeployedSucceedsWhenPresent() external {
        bytes memory tables = LibDecimalFloatDeploy.combinedTables();
        bytes memory creationCode = LibDataContract.contractCreationCode(tables);
        address temp;
        assembly ("memory-safe") {
            temp := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        require(temp != address(0), "log tables deploy failed in test setup");
        vm.etch(LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS, temp.code);
        // Should not revert.
        this.callCheckLogTablesDeployed();
    }

    /// Mutation: with correct etch the call succeeds; replacing the runtime
    /// with same-length zeroes flips the codehash and the call reverts.
    /// Confirms the test is keyed on the codehash check, not anything else.
    function testCheckLogTablesDeployedMutation() external {
        bytes memory tables = LibDecimalFloatDeploy.combinedTables();
        bytes memory creationCode = LibDataContract.contractCreationCode(tables);
        address temp;
        assembly ("memory-safe") {
            temp := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        vm.etch(LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS, temp.code);
        this.callCheckLogTablesDeployed();

        bytes memory zeros = new bytes(temp.code.length);
        vm.etch(LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS, zeros);
        vm.expectRevert();
        this.callCheckLogTablesDeployed();
    }

    /// `vm.expectRevert` only catches reverts in external calls, so wrap the
    /// internal lib call.
    function callCheckLogTablesDeployed() external view {
        LibDecimalFloatDeploy.checkLogTablesDeployed();
    }
}
