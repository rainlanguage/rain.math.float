// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {AddSubRoundOnceHalmosTest} from "./AddSubRoundOnce.halmos.t.sol";

/// `Impl.add` with a tenth of the coefficient two exponents above. `checkSum`
/// reads every t other than D as D + 1, so only NEAR's exponent assertion
/// rejects t = D + 2.
contract AddSubRoundOnceAddTenfoldTest is Test, AddSubRoundOnceHalmosTest {
    function implAdd(int256 ca, int256 ea, int256 cb, int256 eb) external pure override returns (int256, int256) {
        (int256 c, int256 e) = LibDecimalFloatImplementation.add(ca, ea, cb, eb);
        return (c / 10, e + 2);
    }

    /// NEAR: the result exponent is eB + D or eB + D + 1.
    function testNearRejectsAnExponentTwoAbove() external {
        vm.expectRevert(stdError.assertionError);
        this.check_addNear(1e76, 1e75, 0, 5, false);
    }
}
