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
///
/// The registry half is asserted unconditionally too, by handing the script a
/// fixture in place of a fetched response. That keeps three things off the
/// network: that a published version with no pinned suite is reported, that the
/// version scan reads a response whatever whitespace it carries, and that a
/// response no version can be read out of is a failure rather than the skip an
/// unreachable registry earns.
contract LibDecimalFloatDeployTaggedConstantsTest is Test {
    string constant SCRIPT = "script/check-published-deploy-constants.sh";
    string constant HALF_PINNED_FIXTURE = "test/fixtures/half-pinned-deploy-constants.txt";
    string constant UNPINNED_VERSION_RESPONSE_FIXTURE = "test/fixtures/registry-response-unpinned-version.txt";
    string constant PRETTY_PRINTED_RESPONSE_FIXTURE = "test/fixtures/registry-response-pretty-printed.txt";
    string constant UNREADABLE_RESPONSE_FIXTURE = "test/fixtures/registry-response-unreadable.txt";

    /// Every readable fixture response publishes 9.9.9, a version
    /// `LibDecimalFloatDeploy` pins nothing for, so the whole suite is absent.
    string constant UNPINNED_9_9_9 =
        "MISSING: DECIMAL_FLOAT_CONTRACT_HASH_9_9_9 LOG_TABLES_DATA_CONTRACT_HASH_9_9_9 ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS_9_9_9 ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS_9_9_9";

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

    /// A version published to the registry with none of its deploy constants
    /// pinned must be reported by name. That is the registry half's whole
    /// point, and it is the assertion that only ran when api.soldeer.xyz
    /// answered until this test drove it from a fixture.
    function testRegistryCheckReportsAPublishedVersionWithNoPinnedConstants() external {
        assertEq(
            _checkAgainstRegistryResponse(UNPINNED_VERSION_RESPONSE_FIXTURE),
            UNPINNED_9_9_9,
            "the registry check failed to report a published version with no pinned constants"
        );
    }

    /// Whitespace inside the response carries no meaning, so a pretty-printed
    /// answer must read exactly like a compact one. A scan that only matched
    /// the compact spelling would read no versions out of a perfectly good
    /// response and condemn it as unreadable.
    function testRegistryCheckReadsAPrettyPrintedResponse() external {
        assertEq(
            _checkAgainstRegistryResponse(PRETTY_PRINTED_RESPONSE_FIXTURE),
            UNPINNED_9_9_9,
            "the registry check could not read a pretty-printed response"
        );
    }

    /// A response that arrives and carries no readable version is a failure,
    /// not a skip. Calling it a skip retires the registry half the moment the
    /// response shape changes, and every run stays green while that half checks
    /// nothing.
    function testRegistryCheckFailsOnAResponseWithNoReadableVersion() external {
        assertEq(
            _checkAgainstRegistryResponse(UNREADABLE_RESPONSE_FIXTURE),
            "UNREADABLE: the soldeer registry answered but no version could be read from the response; the registry half did not run",
            "an unreadable registry response was not reported as a failure"
        );
    }

    /// Both halves against the committed lib, with `fixture` standing in for a
    /// fetched registry response so the registry half never touches the
    /// network.
    function _checkAgainstRegistryResponse(string memory fixture) private returns (string memory) {
        string[] memory cmd = new string[](4);
        cmd[0] = "bash";
        cmd[1] = SCRIPT;
        cmd[2] = "--registry-response";
        cmd[3] = fixture;
        return string(vm.ffi(cmd));
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
