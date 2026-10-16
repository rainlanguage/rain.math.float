// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {AddSubRoundOnceHalmosTest} from "./AddSubRoundOnce.halmos.t.sol";

/// `Impl.add` with the coefficient one above. The NEAR pair is a = b = 1e76
/// at gap 5, whose exact sum 1e76 + 1e71 at eA is the result; the FAR pair
/// is the same operands at gap 77, where the result is A.
contract AddSubRoundOnceAddCoefficientAboveTest is Test, AddSubRoundOnceHalmosTest {
    function implAdd(int256 ca, int256 ea, int256 cb, int256 eb) external pure override returns (int256, int256) {
        (int256 c, int256 e) = LibDecimalFloatImplementation.add(ca, ea, cb, eb);
        return (c + 1, e);
    }

    /// ZERO: the other operand's coefficient must come back unchanged.
    function testZeroRejectsAChangedCoefficient() external {
        vm.expectRevert(stdError.assertionError);
        this.check_addZeroOperand(5, 3, -2, true);
    }

    /// NEAR: |c| 10^t must not exceed |S|.
    function testNearRejectsAResultAboveTheSum() external {
        vm.expectRevert(stdError.assertionError);
        this.check_addNear(1e76, 1e75, 0, 5, false);
    }

    /// FAR: the magnitude is |A| when the signs agree.
    function testFarRejectsAChangedMagnitude() external {
        vm.expectRevert(stdError.assertionError);
        this.check_addFar(1e76, 1e76, 0, 77, false);
    }
}
