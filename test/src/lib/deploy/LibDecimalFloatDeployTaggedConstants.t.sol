// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";

/// @title LibDecimalFloatDeployTaggedConstantsTest
/// @notice Every version published to the soldeer registry for `rain-math-float`
/// must have a full suite of pinned deploy constants in `LibDecimalFloatDeploy`:
/// a log-tables address + codehash and a DecimalFloat address + codehash for
/// each published version.
///
/// `script/check-published-deploy-constants.sh` splits that into a structural
/// half (every version suffix carrying any pinned constant carries all four —
/// pure file inspection) and a registry half (every published version is
/// pinned — needs api.soldeer.xyz). The structural half is asserted
/// unconditionally here, so a run that cannot reach the registry still verifies
/// something real rather than verifying nothing.
contract LibDecimalFloatDeployTaggedConstantsTest is Test {
    string constant SCRIPT = "script/check-published-deploy-constants.sh";
    string constant HALF_PINNED_FIXTURE = "test/fixtures/half-pinned-deploy-constants.txt";

    /// Structural half against the committed lib. No network, so this asserts
    /// on every run: a version pinned halfway fails here.
    function testEveryPinnedVersionGroupIsComplete() external {
        string[] memory cmd = new string[](3);
        cmd[0] = "bash";
        cmd[1] = SCRIPT;
        cmd[2] = "--offline";
        assertEq(string(vm.ffi(cmd)), "OK", "a pinned version is missing part of its deploy constant suite");
    }

    /// The structural half must actually detect a half-pinned version, not just
    /// report OK for everything. Without this, a check that inspected nothing
    /// would pass `testEveryPinnedVersionGroupIsComplete` just as happily.
    function testStructuralCheckDetectsAHalfPinnedVersion() external {
        string[] memory cmd = new string[](5);
        cmd[0] = "bash";
        cmd[1] = SCRIPT;
        cmd[2] = "--offline";
        cmd[3] = "--lib";
        cmd[4] = HALF_PINNED_FIXTURE;
        assertEq(
            string(vm.ffi(cmd)),
            "MISSING: DECIMAL_FLOAT_CONTRACT_HASH_9_9_9 LOG_TABLES_DATA_CONTRACT_HASH_9_9_9",
            "the structural check failed to report a half-pinned version"
        );
    }

    /// Both halves. Publishing a soldeer tag without pinning its deploy
    /// constants fails here.
    function testAllPublishedSoldeerTagsHaveAFullConstantSuite() external {
        string[] memory cmd = new string[](2);
        cmd[0] = "bash";
        cmd[1] = SCRIPT;
        bytes memory out = vm.ffi(cmd);

        // api.soldeer.xyz was unreachable, so the registry half did not run.
        // This is a pass on what was checked, NOT a skip: the structural half
        // ran and passed inside the same invocation, and is asserted outright
        // by testEveryPinnedVersionGroupIsComplete above. Only "is every
        // PUBLISHED version pinned" is unverifiable without the network,
        // because the set of published versions lives on the registry. The
        // reason is logged so a green run that never reached the registry says
        // so, instead of looking like a full check.
        if (_startsWith(out, bytes("SKIP"))) {
            console2.log(string(out));
            return;
        }

        // On failure the actual value lists the missing `*_<version>` constants.
        assertEq(string(out), "OK", "a published soldeer tag is missing pinned deploy constants");
    }

    function _startsWith(bytes memory s, bytes memory prefix) private pure returns (bool) {
        if (s.length < prefix.length) {
            return false;
        }
        for (uint256 i = 0; i < prefix.length; i++) {
            if (s[i] != prefix[i]) {
                return false;
            }
        }
        return true;
    }
}
