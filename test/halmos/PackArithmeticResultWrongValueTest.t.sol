// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "../../src/lib/LibDecimalFloat.sol";
import {PackArithmeticResultHalmosTest} from "./PackArithmeticResult.halmos.t.sol";

/// `pack` returning the next Float up.
contract PackArithmeticResultWrongValueTest is Test, PackArithmeticResultHalmosTest {
    function pack(int256 c, int256 e) external pure override returns (Float) {
        if (c == 1 && e == 0) return LibDecimalFloat.packLossless(2, 0);
        return LibDecimalFloat.packArithmeticResult(c, e);
    }

    /// PACK: the result's value is the oracle's.
    function testPackRejectsAWrongValue() external {
        vm.expectRevert(stdError.assertionError);
        this.check_packMiddle(1, 0, 0);
    }
}
