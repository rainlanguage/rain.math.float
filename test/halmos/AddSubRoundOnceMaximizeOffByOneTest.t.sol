// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {AddSubRoundOnceHalmosTest} from "./AddSubRoundOnce.halmos.t.sol";

/// `maximize` with the coefficient one above the exact product.
contract AddSubRoundOnceMaximizeOffByOneTest is Test, AddSubRoundOnceHalmosTest {
    function maximize(int256 c, int256 e) external pure override returns (int256, int256, int256) {
        (int256 m, int256 me,) = LibDecimalFloatImplementation.maximize(c, e);
        return (m + 1, me, 0);
    }

    /// MAX: m must be c 10^k exactly; the shift and the magnitude bounds
    /// still hold for 10^76 + 1.
    function testMaxRejectsAnInexactProduct() external {
        vm.expectRevert(stdError.assertionError);
        this.check_maximizeFloat(1, 0, 0);
    }

    /// IDEM: a maximized coefficient must come back unchanged.
    function testIdemRejectsAChangedCoefficient() external {
        vm.expectRevert(stdError.assertionError);
        this.check_maximizeIdempotent(1e76, 0);
    }
}
