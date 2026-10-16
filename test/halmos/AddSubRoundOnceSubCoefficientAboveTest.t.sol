// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {AddSubRoundOnceHalmosTest} from "./AddSubRoundOnce.halmos.t.sol";

/// `Impl.sub` with the coefficient one above the negated `Impl.add`'s.
contract AddSubRoundOnceSubCoefficientAboveTest is Test, AddSubRoundOnceHalmosTest {
    function implSub(int256 ca, int256 ea, int256 cb, int256 eb) external pure override returns (int256, int256) {
        (int256 c, int256 e) = LibDecimalFloatImplementation.add(ca, ea, -cb, eb);
        return (c + 1, e);
    }

    /// MINUS: the two outputs are byte-identical.
    function testMinusRejectsAChangedCoefficient() external {
        vm.expectRevert(stdError.assertionError);
        this.check_subIsAddNegated(1, 1, 0, 0, 0, 0);
    }
}
