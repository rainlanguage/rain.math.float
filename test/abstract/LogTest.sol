// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {DataContractMemoryContainer, LibDataContract} from "rain.datacontract/lib/LibDataContract.sol";
import {LibDecimalFloatDeploy} from "src/lib/LibDecimalFloatDeploy.sol";

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
