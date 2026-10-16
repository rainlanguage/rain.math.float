// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "../../src/lib/LibDecimalFloat.sol";
import {PackArithmeticResultHalmosTest} from "./PackArithmeticResult.halmos.t.sol";

/// `pack` returning a zero coefficient at exponent one for zero.
contract PackArithmeticResultNonCanonicalZeroTest is Test, PackArithmeticResultHalmosTest {
    function pack(int256 c, int256 e) external pure override returns (Float) {
        if (c == 0) return Float.wrap(bytes32(uint256(1) << 224));
        return LibDecimalFloat.packArithmeticResult(c, e);
    }

    /// PACK: zero is all bits zero.
    function testPackRejectsANonCanonicalZero() external {
        vm.expectRevert(stdError.assertionError);
        this.check_packMiddle(0, 5, 0);
    }
}
