// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "../../src/lib/LibDecimalFloat.sol";
import {ExponentOverflow, ExponentUnderflow} from "../../src/error/ErrDecimalFloat.sol";
import {PackArithmeticResultHalmosTest} from "./PackArithmeticResult.halmos.t.sol";

/// `pack` reverting with the other error: `ExponentOverflow` below the
/// exponent floor and `ExponentUnderflow` above the ceiling.
contract PackArithmeticResultSwappedErrorsTest is Test, PackArithmeticResultHalmosTest {
    function pack(int256 c, int256 e) external pure override returns (Float) {
        if (c != 0 && e <= FMIN - 78) revert ExponentOverflow(c, e);
        if (c != 0 && e >= FMAX + 68) revert ExponentUnderflow(c, e);
        return LibDecimalFloat.packArithmeticResult(c, e);
    }

    /// PACK: a zero result for nonzero c is `ExponentUnderflow`.
    function testPackRejectsOverflowForUnderflow() external {
        vm.expectRevert(stdError.assertionError);
        this.check_packBelow(1, FMIN - 78, 0);
    }

    /// PACK: a value past every Float is `ExponentOverflow`.
    function testPackRejectsUnderflowForOverflow() external {
        vm.expectRevert(stdError.assertionError);
        this.check_packAbove(1, FMAX + 68, 0);
    }
}
