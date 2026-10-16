// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {LibHalmosExactHalmosTest} from "./LibHalmosExact.halmos.t.sol";

/// The hint filters reporting false.
contract LibHalmosExactHoldsFalseTest is Test, LibHalmosExactHalmosTest {
    function maximizeHintsOf(int256, uint256) external pure override returns (bool) {
        return false;
    }

    function packHintsOf(int256, uint256) external pure override returns (bool) {
        return false;
    }

    function divHintOf(int256, int256) external pure override returns (bool) {
        return false;
    }

    function testMaximizeHoldRejectsAFalseFilter() external {
        vm.expectRevert(stdError.assertionError);
        this.check_maximizeHintsHold(1, 0);
    }

    function testPackHoldRejectsAFalseFilter() external {
        vm.expectRevert(stdError.assertionError);
        this.check_packHintsHold(1, 0);
    }

    function testDivHintHoldRejectsAFalseFilter() external {
        vm.expectRevert(stdError.assertionError);
        this.check_divHintHolds(0);
    }
}
