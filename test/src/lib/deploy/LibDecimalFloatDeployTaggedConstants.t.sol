// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibDataContract} from "rain-datacontract-0.1.0/src/lib/LibDataContract.sol";
import {LibRainDeploy} from "rain-deploy-0.1.3/src/lib/LibRainDeploy.sol";
import {LibDecimalFloatDeploy} from "src/lib/deploy/LibDecimalFloatDeploy.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

import {
    LOG_TABLES_DEPLOYED_ADDRESS as LOG_TABLES_ADDRESS_0_1_1,
    LOG_TABLES_DEPLOYED_CODEHASH as LOG_TABLES_CODEHASH_0_1_1,
    DECIMAL_FLOAT_DEPLOYED_ADDRESS as DECIMAL_FLOAT_ADDRESS_0_1_1,
    DECIMAL_FLOAT_DEPLOYED_CODEHASH as DECIMAL_FLOAT_CODEHASH_0_1_1
} from "src/generated/0_1_1/DecimalFloatDeploy.pointers.sol";
import {
    LOG_TABLES_DEPLOYED_ADDRESS as LOG_TABLES_ADDRESS_0_1_7,
    LOG_TABLES_DEPLOYED_CODEHASH as LOG_TABLES_CODEHASH_0_1_7,
    DECIMAL_FLOAT_DEPLOYED_ADDRESS as DECIMAL_FLOAT_ADDRESS_0_1_7,
    DECIMAL_FLOAT_DEPLOYED_CODEHASH as DECIMAL_FLOAT_CODEHASH_0_1_7
} from "src/generated/0_1_7/DecimalFloatDeploy.pointers.sol";

/// @title LibDecimalFloatDeployTaggedConstantsTest
/// @notice Every release keeps its deployment record in a frozen snapshot under
/// `src/generated/<tag>/DecimalFloatDeploy.pointers.sol`. Both deployables are
/// placed by Zoltu's deterministic proxy, so every address is a pure function of
/// its creation code and the whole record is reproducible OFFLINE — these tests
/// need no network, no registry, and no skips.
contract LibDecimalFloatDeployTaggedConstantsTest is Test {
    /// The current release's pinned deploy constants must be exactly what this
    /// source tree produces. Regenerating them here is the same computation
    /// `script/BuildPointers.sol` performs, so this fails the moment the log
    /// tables or `DecimalFloat` change without the deploy pointers being
    /// regenerated — i.e. it catches pin-vs-code drift deterministically.
    function testCurrentDeploymentRecordReproduces() external {
        LibRainDeploy.etchZoltuFactory(vm);

        // The log tables must land first: DecimalFloat's constructor calls
        // checkLogTablesDeployed(), which reads the codehash at their address.
        address logTables =
            LibRainDeploy.deployZoltu(LibDataContract.contractCreationCode(LibDecimalFloatDeploy.combinedTables()));
        assertEq(logTables, LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS, "log tables address drifted");
        assertEq(logTables.codehash, LibDecimalFloatDeploy.LOG_TABLES_DATA_CONTRACT_HASH, "log tables codehash drifted");

        address decimalFloat = LibRainDeploy.deployZoltu(type(DecimalFloat).creationCode);
        assertEq(
            decimalFloat, LibDecimalFloatDeploy.ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS, "DecimalFloat address drifted"
        );
        assertEq(
            decimalFloat.codehash, LibDecimalFloatDeploy.DECIMAL_FLOAT_CONTRACT_HASH, "DecimalFloat codehash drifted"
        );
    }

    /// Every frozen snapshot carries its FULL suite: a log-tables address +
    /// codehash and a DecimalFloat address + codehash. A missing constant fails
    /// to compile (the named imports above are the completeness check); a
    /// placeholder/zero value fails here.
    function testEveryFrozenSnapshotHasItsFullSuite() external pure {
        assertNotEq(LOG_TABLES_ADDRESS_0_1_1, address(0), "0.1.1 log tables address");
        assertNotEq(LOG_TABLES_CODEHASH_0_1_1, bytes32(0), "0.1.1 log tables codehash");
        assertNotEq(DECIMAL_FLOAT_ADDRESS_0_1_1, address(0), "0.1.1 DecimalFloat address");
        assertNotEq(DECIMAL_FLOAT_CODEHASH_0_1_1, bytes32(0), "0.1.1 DecimalFloat codehash");

        assertNotEq(LOG_TABLES_ADDRESS_0_1_7, address(0), "0.1.7 log tables address");
        assertNotEq(LOG_TABLES_CODEHASH_0_1_7, bytes32(0), "0.1.7 log tables codehash");
        assertNotEq(DECIMAL_FLOAT_ADDRESS_0_1_7, address(0), "0.1.7 DecimalFloat address");
        assertNotEq(DECIMAL_FLOAT_CODEHASH_0_1_7, bytes32(0), "0.1.7 DecimalFloat codehash");
    }

    /// The snapshot for the CURRENT release must match the live constants — the
    /// current release is the one this source tree builds, so its frozen record
    /// and the constants the library exposes cannot diverge.
    function testCurrentReleaseSnapshotMatchesLiveConstants() external pure {
        assertEq(LOG_TABLES_ADDRESS_0_1_7, LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS);
        assertEq(LOG_TABLES_CODEHASH_0_1_7, LibDecimalFloatDeploy.LOG_TABLES_DATA_CONTRACT_HASH);
        assertEq(DECIMAL_FLOAT_ADDRESS_0_1_7, LibDecimalFloatDeploy.ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS);
        assertEq(DECIMAL_FLOAT_CODEHASH_0_1_7, LibDecimalFloatDeploy.DECIMAL_FLOAT_CONTRACT_HASH);
    }
}
