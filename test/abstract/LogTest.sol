// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

// Re-export console2 here for convenience.
// forge-lint: disable-next-line(unused-import)
import {Test, console2} from "forge-std-1.16.1/src/Test.sol";
import {DataContractMemoryContainer, LibDataContract} from "rain-datacontract-0.1.0/src/lib/LibDataContract.sol";
import {LibDecimalFloatDeploy} from "src/lib/deploy/LibDecimalFloatDeploy.sol";
import {LibEtchLogTables} from "script/lib/LibEtchLogTables.sol";

abstract contract LogTest is Test {
    using LibDataContract for DataContractMemoryContainer;

    address sTables;

    /// Etch the log tables runtime at the Zoltu-deterministic deployment
    /// address used by the production `DecimalFloat` contract. Without this,
    /// the deployed tests below would `extcodecopy` from an empty address
    /// while the external helper does the same, both agreeing on garbage.
    function setUp() public virtual {
        LibEtchLogTables.etchLogTables(vm);
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
