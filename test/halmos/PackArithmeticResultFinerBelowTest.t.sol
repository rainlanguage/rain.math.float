// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "../../src/lib/LibDecimalFloat.sol";
import {PackArithmeticResultHalmosTest} from "./PackArithmeticResult.halmos.t.sol";

/// `pack` returning 49 10^-1 for 5 10^0: below the value at an exponent finer
/// than the oracle's, so `eqValue` compares it in its `re < se` branch.
contract PackArithmeticResultFinerBelowTest is Test, PackArithmeticResultHalmosTest {
    function pack(int256 c, int256 e) external pure override returns (Float) {
        if (c == 5 && e == 0) return LibDecimalFloat.packLossless(49, -1);
        return LibDecimalFloat.packArithmeticResult(c, e);
    }

    /// PACK: the result's value is the oracle's, not just at most it.
    function testPackRejectsALowerValueAtAFinerExponent() external {
        vm.expectRevert(stdError.assertionError);
        this.check_packMiddle(5, 0, 0);
    }
}
