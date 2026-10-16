// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "../../src/lib/LibDecimalFloat.sol";
import {PackArithmeticResultHalmosTest} from "./PackArithmeticResult.halmos.t.sol";

/// `pack` returning zero where the value is below every Float.
contract PackArithmeticResultNoUnderflowTest is Test, PackArithmeticResultHalmosTest {
    function pack(int256 c, int256 e) external pure override returns (Float) {
        if (c != 0 && e <= FMIN - 78) return Float.wrap(bytes32(0));
        return LibDecimalFloat.packArithmeticResult(c, e);
    }

    /// PACK: a zero result for nonzero c reverts.
    function testPackRejectsAMissingRevert() external {
        vm.expectRevert(stdError.assertionError);
        this.check_packBelow(1, FMIN - 78, 0);
    }
}
