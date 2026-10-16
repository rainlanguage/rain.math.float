// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "../../src/lib/LibDecimalFloat.sol";
import {ExponentUnderflow} from "../../src/error/ErrDecimalFloat.sol";
import {PackArithmeticResultHalmosTest} from "./PackArithmeticResult.halmos.t.sol";

/// `pack` reverting with a word appended to the right error.
contract PackArithmeticResultErrorTrailingBytesTest is Test, PackArithmeticResultHalmosTest {
    function pack(int256 c, int256 e) external pure override returns (Float) {
        if (c != 0 && e <= FMIN - 78) {
            bytes memory data = abi.encodePacked(abi.encodeWithSelector(ExponentUnderflow.selector, c, e), bytes32(0));
            assembly ("memory-safe") {
                revert(add(data, 0x20), mload(data))
            }
        }
        return LibDecimalFloat.packArithmeticResult(c, e);
    }

    /// PACK: the error is exactly a selector and two words.
    function testPackRejectsALongerError() external {
        vm.expectRevert(stdError.assertionError);
        this.check_packBelow(1, FMIN - 78, 0);
    }
}
