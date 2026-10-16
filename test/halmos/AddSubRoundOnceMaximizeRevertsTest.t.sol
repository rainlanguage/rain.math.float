// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {AddSubRoundOnceHalmosTest} from "./AddSubRoundOnce.halmos.t.sol";

/// `maximize` reverting for every input.
contract AddSubRoundOnceMaximizeRevertsTest is Test, AddSubRoundOnceHalmosTest {
    error Reverted();

    function maximize(int256, int256) external pure override returns (int256, int256, int256) {
        revert Reverted();
    }

    /// MAX: maximizing an int224 coefficient at an int32 exponent does not
    /// revert.
    function testMaxRejectsARevert() external {
        vm.expectRevert(stdError.assertionError);
        this.check_maximizeFloat(1, 0, 0);
    }

    /// IDEM: maximizing a maximized coefficient does not revert.
    function testIdemRejectsARevert() external {
        vm.expectRevert(stdError.assertionError);
        this.check_maximizeIdempotent(1e76, 0);
    }
}
