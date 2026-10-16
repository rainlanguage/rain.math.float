// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {AddSubRoundOnceHalmosTest} from "./AddSubRoundOnce.halmos.t.sol";

/// `Impl.add` returning the maximized zero for every input.
contract AddSubRoundOnceAddZeroTest is Test, AddSubRoundOnceHalmosTest {
    function implAdd(int256, int256, int256, int256) external pure override returns (int256, int256) {
        return (0, 0);
    }

    /// NEAR: a nonzero sum has a nonzero result.
    function testNearRejectsAZeroForANonzeroSum() external {
        vm.expectRevert(stdError.assertionError);
        this.check_addNear(1e76, 1e75, 0, 5, false);
    }
}
