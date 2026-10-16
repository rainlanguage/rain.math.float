// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {AddSubRoundOnceHalmosTest} from "./AddSubRoundOnce.halmos.t.sol";

/// `Impl.add` reverting for every input.
contract AddSubRoundOnceAddRevertsTest is Test, AddSubRoundOnceHalmosTest {
    error Reverted();

    function implAdd(int256, int256, int256, int256) external pure override returns (int256, int256) {
        revert Reverted();
    }

    /// ZERO: adding a zero operand does not revert.
    function testZeroRejectsARevert() external {
        vm.expectRevert(stdError.assertionError);
        this.check_addZeroOperand(5, 3, -2, false);
    }

    /// NEAR: adding maximized operands does not revert.
    function testNearRejectsARevert() external {
        vm.expectRevert(stdError.assertionError);
        this.check_addNear(1e76, 1e75, 0, 5, false);
    }

    /// FAR: adding maximized operands does not revert.
    function testFarRejectsARevert() external {
        vm.expectRevert(stdError.assertionError);
        this.check_addFar(1e76, 1e76, 0, 77, false);
    }
}
