// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";
import {LibDecimalFloatDeploy} from "src/lib/deploy/LibDecimalFloatDeploy.sol";
import {LibDataContract} from "rain-datacontract-0.1.0/src/lib/LibDataContract.sol";
import {LogTablesNotDeployed} from "src/error/ErrDecimalFloat.sol";

/// Direct tests for the `DecimalFloat` constructor's log-tables guard. These
/// tests deliberately do NOT inherit `LogTest` so the table address is empty
/// at the start, letting the test choose what (if anything) to deploy there.
contract DecimalFloatConstructorTest is Test {
    /// Without log tables at the expected address, the constructor reverts.
    function testConstructorRevertsWhenLogTablesMissing() external {
        bytes32 actualCodehash = LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS.codehash;
        vm.expectRevert(
            abi.encodeWithSelector(
                LogTablesNotDeployed.selector,
                LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS,
                LibDecimalFloatDeploy.LOG_TABLES_DATA_CONTRACT_HASH,
                actualCodehash
            )
        );
        new DecimalFloat();
    }

    /// With unrelated bytecode at the expected address, the codehash mismatch
    /// trips the guard.
    function testConstructorRevertsOnWrongCodehash() external {
        // Etch arbitrary bytes so the codehash differs from the expected.
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
        new DecimalFloat();
    }

    /// With the correct log tables runtime etched at the expected address,
    /// the constructor succeeds.
    function testConstructorSucceedsWhenLogTablesPresent() external {
        bytes memory tables = LibDecimalFloatDeploy.combinedTables();
        bytes memory creationCode = LibDataContract.contractCreationCode(tables);
        address temp;
        assembly ("memory-safe") {
            temp := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        require(temp != address(0), "log tables deploy failed in test setup");
        vm.etch(LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS, temp.code);
        // Should NOT revert.
        DecimalFloat decimalFloat = new DecimalFloat();
        assertTrue(address(decimalFloat) != address(0));
    }

    /// Mutation guard: confirm the constructor's revert is detecting the
    /// wrong-codehash path, not just any contract-creation issue. With
    /// matching codehash but the right runtime, construction succeeds; with
    /// mismatched bytes, construction reverts. The two outcomes diverge only
    /// on the codehash check.
    function testConstructorMutation() external {
        // First half: correct etch — must succeed.
        bytes memory tables = LibDecimalFloatDeploy.combinedTables();
        bytes memory creationCode = LibDataContract.contractCreationCode(tables);
        address temp;
        assembly ("memory-safe") {
            temp := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        require(temp != address(0), "log tables deploy failed in mutation setup");
        vm.etch(LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS, temp.code);
        new DecimalFloat();

        // Mutation: replace the tables runtime with the same length of zero
        // bytes. The codehash now mismatches LOG_TABLES_DATA_CONTRACT_HASH.
        bytes memory zeros = new bytes(temp.code.length);
        vm.etch(LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS, zeros);
        bytes32 zeroBytesCodehash = keccak256(zeros);
        vm.expectRevert(
            abi.encodeWithSelector(
                LogTablesNotDeployed.selector,
                LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS,
                LibDecimalFloatDeploy.LOG_TABLES_DATA_CONTRACT_HASH,
                zeroBytesCodehash
            )
        );
        new DecimalFloat();
    }
}
