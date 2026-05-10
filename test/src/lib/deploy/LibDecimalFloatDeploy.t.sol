// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.2/src/lib/LibRainDeploy.sol";
import {LibDecimalFloatDeploy} from "src/lib/deploy/LibDecimalFloatDeploy.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";
import {LibDataContract} from "rain-datacontract-0.1.0/src/lib/LibDataContract.sol";

contract LibDecimalFloatDeployTest is Test {
    /// `LibRainDeploy.etchZoltuFactory` puts the factory bytecode at the
    /// deterministic factory address using `vm.etch`. No fork required —
    /// the test runs entirely in-memory, which avoids RPC-flake and the
    /// "address already has code" collision when a deploy target is
    /// already populated on the chosen prod chain.
    function setUp() public {
        LibRainDeploy.etchZoltuFactory(vm);
    }

    function testDeployAddress() external {
        // The `DecimalFloat` constructor checks the log tables are at the
        // expected address with the expected codehash. Deploy them first.
        bytes memory logTables = LibDataContract.contractCreationCode(LibDecimalFloatDeploy.combinedTables());
        LibRainDeploy.deployZoltu(logTables);

        address deployedAddress = LibRainDeploy.deployZoltu(type(DecimalFloat).creationCode);

        assertEq(deployedAddress, LibDecimalFloatDeploy.ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS);
        assertTrue(address(deployedAddress).code.length > 0, "Deployed address has no code");

        assertEq(address(deployedAddress).codehash, LibDecimalFloatDeploy.DECIMAL_FLOAT_CONTRACT_HASH);
    }

    function testExpectedCodeHashDecimalFloat() external {
        // `new DecimalFloat()` triggers the constructor's log-tables guard;
        // deploy them via Zoltu first.
        bytes memory logTables = LibDataContract.contractCreationCode(LibDecimalFloatDeploy.combinedTables());
        LibRainDeploy.deployZoltu(logTables);

        DecimalFloat decimalFloat = new DecimalFloat();

        assertEq(address(decimalFloat).codehash, LibDecimalFloatDeploy.DECIMAL_FLOAT_CONTRACT_HASH);
    }

    function testDeployAddressLogTables() external {
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
