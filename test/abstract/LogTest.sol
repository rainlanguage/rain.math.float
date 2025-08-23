// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

// Re-export console2 here for convenience.
import {Test, console2} from "forge-std/Test.sol";
import {DataContractMemoryContainer, LibDataContract} from "rain.datacontract/lib/LibDataContract.sol";
import {LibDecimalFloatDeploy} from "src/lib/deploy/LibDecimalFloatDeploy.sol";

abstract contract LogTest is Test {
    using LibDataContract for DataContractMemoryContainer;

    address sTables;

    function logTables() internal returns (address) {
        if (sTables == address(0)) {
            DataContractMemoryContainer container = LibDecimalFloatDeploy.dataContract();
            sTables = container.write();
        }
        return sTables;
    }
}
