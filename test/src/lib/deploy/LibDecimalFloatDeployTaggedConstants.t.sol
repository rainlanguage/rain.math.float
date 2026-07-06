// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

/// @title LibDecimalFloatDeployTaggedConstantsTest
/// @notice Every version published to the soldeer registry for `rain-math-float`
/// must have a full suite of pinned deploy constants in `LibDecimalFloatDeploy`:
/// a log-tables address + codehash and a DecimalFloat address + codehash for
/// each published version. `script/check-published-deploy-constants.sh` queries
/// the live registry (via FFI) and lists any missing constants, so publishing a
/// new tag without pinning its constants fails this test. Skips if the registry
/// is unreachable rather than failing on network flakiness.
contract LibDecimalFloatDeployTaggedConstantsTest is Test {
    function testAllPublishedSoldeerTagsHaveAFullConstantSuite() external {
        string[] memory cmd = new string[](2);
        cmd[0] = "bash";
        cmd[1] = "script/check-published-deploy-constants.sh";
        bytes memory out = vm.ffi(cmd);

        // The registry could not be reached; there is nothing to verify.
        if (_startsWith(out, bytes("SKIP"))) {
            vm.skip(true);
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
