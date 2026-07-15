// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "rain-deploy-0.1.3/src/lib/LibRainDeploy.sol";
import {LibDecimalFloatDeploy} from "src/lib/deploy/LibDecimalFloatDeploy.sol";

import {
    DEPLOYED_ADDRESS as LOG_TABLES_ADDRESS_0_1_1,
    BYTECODE_HASH as LOG_TABLES_CODEHASH_0_1_1,
    CREATION_CODE as LOG_TABLES_CREATION_CODE_0_1_1,
    RUNTIME_CODE as LOG_TABLES_RUNTIME_CODE_0_1_1
} from "src/generated/0_1_1/LogTablesDeploy.sol";
import {
    DEPLOYED_ADDRESS as DECIMAL_FLOAT_ADDRESS_0_1_1,
    BYTECODE_HASH as DECIMAL_FLOAT_CODEHASH_0_1_1,
    CREATION_CODE as DECIMAL_FLOAT_CREATION_CODE_0_1_1,
    RUNTIME_CODE as DECIMAL_FLOAT_RUNTIME_CODE_0_1_1
} from "src/generated/0_1_1/DecimalFloatDeploy.sol";
import {
    DEPLOYED_ADDRESS as LOG_TABLES_ADDRESS_0_1_7,
    BYTECODE_HASH as LOG_TABLES_CODEHASH_0_1_7,
    CREATION_CODE as LOG_TABLES_CREATION_CODE_0_1_7,
    RUNTIME_CODE as LOG_TABLES_RUNTIME_CODE_0_1_7
} from "src/generated/0_1_7/LogTablesDeploy.sol";
import {
    DEPLOYED_ADDRESS as DECIMAL_FLOAT_ADDRESS_0_1_7,
    BYTECODE_HASH as DECIMAL_FLOAT_CODEHASH_0_1_7,
    CREATION_CODE as DECIMAL_FLOAT_CREATION_CODE_0_1_7,
    RUNTIME_CODE as DECIMAL_FLOAT_RUNTIME_CODE_0_1_7
} from "src/generated/0_1_7/DecimalFloatDeploy.sol";

/// @title LibDecimalFloatDeployTaggedConstantsTest
/// @notice Every release freezes its deployment record under
/// `src/generated/<tag>/`: for each deployable, the Zoltu-deterministic address,
/// its runtime codehash, and the creation + runtime bytecode it shipped.
///
/// Because each snapshot carries its OWN bytecode, every release self-verifies
/// offline and stays reproducible after the current build diverges — no network,
/// no registry, no skips. A record of address + codehash alone could not do this.
contract LibDecimalFloatDeployTaggedConstantsTest is Test {
    /// A frozen record is only trustworthy if the three facts it pins agree with
    /// each other:
    ///   - the runtime bytecode hashes to the pinned codehash, and
    ///   - the creation bytecode deployed through Zoltu lands on the pinned
    ///     address, with that same runtime code on-chain.
    /// Both are pure functions of the frozen bytes, so this holds forever for a
    /// past release regardless of what the current source does.
    function checkFrozenRecord(
        string memory label,
        address deployedAddress,
        bytes32 codehash,
        bytes memory creationCode,
        bytes memory runtimeCode
    ) internal {
        assertEq(keccak256(runtimeCode), codehash, string.concat(label, ": runtime code does not hash to the codehash"));

        address deployed = LibRainDeploy.deployZoltu(creationCode);
        assertEq(deployed, deployedAddress, string.concat(label, ": creation code does not deploy to the address"));
        assertEq(deployed.code, runtimeCode, string.concat(label, ": on-chain runtime differs from the frozen runtime"));
    }

    /// The 0.1.1 release, verified from its own frozen bytecode.
    function testFrozenRecord_0_1_1() external {
        LibRainDeploy.etchZoltuFactory(vm);

        // Log tables first: DecimalFloat's constructor reads their codehash.
        checkFrozenRecord(
            "0.1.1 log tables",
            LOG_TABLES_ADDRESS_0_1_1,
            LOG_TABLES_CODEHASH_0_1_1,
            LOG_TABLES_CREATION_CODE_0_1_1,
            LOG_TABLES_RUNTIME_CODE_0_1_1
        );
        checkFrozenRecord(
            "0.1.1 DecimalFloat",
            DECIMAL_FLOAT_ADDRESS_0_1_1,
            DECIMAL_FLOAT_CODEHASH_0_1_1,
            DECIMAL_FLOAT_CREATION_CODE_0_1_1,
            DECIMAL_FLOAT_RUNTIME_CODE_0_1_1
        );
    }

    /// The 0.1.7 release, verified from its own frozen bytecode.
    function testFrozenRecord_0_1_7() external {
        LibRainDeploy.etchZoltuFactory(vm);

        checkFrozenRecord(
            "0.1.7 log tables",
            LOG_TABLES_ADDRESS_0_1_7,
            LOG_TABLES_CODEHASH_0_1_7,
            LOG_TABLES_CREATION_CODE_0_1_7,
            LOG_TABLES_RUNTIME_CODE_0_1_7
        );
        checkFrozenRecord(
            "0.1.7 DecimalFloat",
            DECIMAL_FLOAT_ADDRESS_0_1_7,
            DECIMAL_FLOAT_CODEHASH_0_1_7,
            DECIMAL_FLOAT_CREATION_CODE_0_1_7,
            DECIMAL_FLOAT_RUNTIME_CODE_0_1_7
        );
    }

    /// Releases must not collapse into each other: 0.1.1 and 0.1.7 shipped
    /// different DecimalFloat bytecode, so their records must differ. If a
    /// "frozen" tag ever re-derived from current source, these would converge.
    function testReleasesAreDistinctHistoricals() external pure {
        assertNotEq(DECIMAL_FLOAT_ADDRESS_0_1_1, DECIMAL_FLOAT_ADDRESS_0_1_7, "DecimalFloat address collapsed");
        assertNotEq(DECIMAL_FLOAT_CODEHASH_0_1_1, DECIMAL_FLOAT_CODEHASH_0_1_7, "DecimalFloat codehash collapsed");
        assertNotEq(
            keccak256(DECIMAL_FLOAT_CREATION_CODE_0_1_1),
            keccak256(DECIMAL_FLOAT_CREATION_CODE_0_1_7),
            "DecimalFloat creation code collapsed"
        );
    }

    /// The CURRENT release's snapshot is what the library exposes. This is the
    /// drift check: change the log tables or DecimalFloat without regenerating,
    /// and the constants no longer match the release they claim to describe.
    function testCurrentReleaseSnapshotMatchesLiveConstants() external pure {
        assertEq(LOG_TABLES_ADDRESS_0_1_7, LibDecimalFloatDeploy.ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS);
        assertEq(LOG_TABLES_CODEHASH_0_1_7, LibDecimalFloatDeploy.LOG_TABLES_DATA_CONTRACT_HASH);
        assertEq(DECIMAL_FLOAT_ADDRESS_0_1_7, LibDecimalFloatDeploy.ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS);
        assertEq(DECIMAL_FLOAT_CODEHASH_0_1_7, LibDecimalFloatDeploy.DECIMAL_FLOAT_CONTRACT_HASH);
    }
}
