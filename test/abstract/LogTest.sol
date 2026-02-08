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
