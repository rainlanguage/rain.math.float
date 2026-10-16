// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "../../src/lib/LibDecimalFloat.sol";
import {PackArithmeticResultHalmosTest} from "./PackArithmeticResult.halmos.t.sol";

/// `pack` returning the value negated: the magnitude is the oracle's, so only
/// `eqValue`'s sign test rejects it.
contract PackArithmeticResultNegatedTest is Test, PackArithmeticResultHalmosTest {
    function pack(int256 c, int256 e) external pure override returns (Float) {
        return LibDecimalFloat.packArithmeticResult(-c, e);
    }

    /// PACK: the result has c's sign.
    function testPackRejectsAWrongSign() external {
        vm.expectRevert(stdError.assertionError);
        this.check_packMiddle(5, 0, 0);
        vm.expectRevert(stdError.assertionError);
        this.check_packMiddle(-5, 0, 0);
    }
}
