// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {AddSubRoundOnceHalmosTest} from "./AddSubRoundOnce.halmos.t.sol";

/// `maximize` reporting a shortfall of one.
contract AddSubRoundOnceMaximizeShortfallTest is Test, AddSubRoundOnceHalmosTest {
    function maximize(int256 c, int256 e) external pure override returns (int256, int256, int256) {
        (int256 m, int256 me,) = LibDecimalFloatImplementation.maximize(c, e);
        return (m, me, 1);
    }

    /// MAX: no shortfall for an int32 exponent.
    function testMaxRejectsAShortfall() external {
        vm.expectRevert(stdError.assertionError);
        this.check_maximizeFloat(1, 0, 0);
    }

    /// IDEM: no shortfall for a maximized input.
    function testIdemRejectsAShortfall() external {
        vm.expectRevert(stdError.assertionError);
        this.check_maximizeIdempotent(1e76, 0);
    }
}
