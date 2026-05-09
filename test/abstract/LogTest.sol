// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

// Re-export console2 here for convenience.
// forge-lint: disable-next-line(unused-import)
import {Test, console2} from "forge-std/Test.sol";
import {DataContractMemoryContainer, LibDataContract} from "rain.datacontract/lib/LibDataContract.sol";
import {LibDecimalFloatDeploy} from "src/lib/deploy/LibDecimalFloatDeploy.sol";

abstract contract LogTest is Test {
    using LibDataContract for DataContractMemoryContainer;

    address sTables;

    /// Etch the log tables runtime at the Zoltu-deterministic deployment
    /// address used by the production `DecimalFloat` contract. Without this,
    /// the `*Deployed` tests below would `extcodecopy` from an empty address,
    /// have both the external helper and the deployed contract agree on
    /// garbage, and pass without verifying anything (the H01-class failure
    /// mode this PR fixes in production).
    function setUp() public virtual {
        bytes memory tables = LibDecimalFloatDeploy.combinedTables();
        bytes memory creationCode = LibDataContract.contractCreationCode(tables);
        address temp;
        assembly ("memory-safe") {
            temp := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        require(temp != address(0), "log tables deploy failed in LogTest.setUp");
        vm.etch(LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS, temp.code);
        assertEq(
            LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS.codehash,
            LibDecimalFloatDeploy.LOG_TABLES_DATA_CONTRACT_HASH,
            "etched tables codehash mismatch"
        );
    }

    function logTables() internal returns (address) {
        if (sTables == address(0)) {
            bytes memory tables = LibDecimalFloatDeploy.combinedTables();
            bytes memory creationCode = LibDataContract.contractCreationCode(tables);
            address tablesAddress;
            assembly ("memory-safe") {
                tablesAddress := create(0, add(creationCode, 0x20), mload(creationCode))
            }
            assertTrue(tablesAddress != address(0), "Failed to deploy tables");
            assertEq(
                tablesAddress.codehash,
                LibDecimalFloatDeploy.LOG_TABLES_DATA_CONTRACT_HASH,
                "Deployed tables codehash does not match expected value"
            );
            sTables = tablesAddress;
        }
        return sTables;
    }
}
