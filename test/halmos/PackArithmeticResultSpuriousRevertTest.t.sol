// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "../../src/lib/LibDecimalFloat.sol";
import {ExponentOverflow} from "../../src/error/ErrDecimalFloat.sol";
import {PackArithmeticResultHalmosTest} from "./PackArithmeticResult.halmos.t.sol";

/// `pack` reverting where the value is a Float, with the error the selector
/// check takes at status 0, so only the status check rejects it.
contract PackArithmeticResultSpuriousRevertTest is Test, PackArithmeticResultHalmosTest {
    function pack(int256 c, int256 e) external pure override returns (Float) {
        if (c == 1 && e == 0) revert ExponentOverflow(c, e);
        return LibDecimalFloat.packArithmeticResult(c, e);
    }

    /// PACK: a Float packs.
    function testPackRejectsASpuriousRevert() external {
        vm.expectRevert(stdError.assertionError);
        this.check_packMiddle(1, 0, 0);
    }
}
