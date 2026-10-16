// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {AddSubRoundOnceHalmosTest} from "./AddSubRoundOnce.halmos.t.sol";

/// `Impl.add` with the exponent one above.
contract AddSubRoundOnceAddExponentAboveTest is Test, AddSubRoundOnceHalmosTest {
    function implAdd(int256 ca, int256 ea, int256 cb, int256 eb) external pure override returns (int256, int256) {
        (int256 c, int256 e) = LibDecimalFloatImplementation.add(ca, ea, cb, eb);
        return (c, e + 1);
    }

    /// ZERO: the other operand's exponent must come back unchanged.
    function testZeroRejectsAChangedExponent() external {
        vm.expectRevert(stdError.assertionError);
        this.check_addZeroOperand(5, 3, -2, false);
    }

    /// FAR: the result exponent is eA.
    function testFarRejectsAChangedExponent() external {
        vm.expectRevert(stdError.assertionError);
        this.check_addFar(1e76, 1e76, 0, 77, false);
    }
}
