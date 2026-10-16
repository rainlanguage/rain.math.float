// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {AddSubRoundOnceHalmosTest} from "./AddSubRoundOnce.halmos.t.sol";

/// `maximize` one shift short: the result is exact and still c 10^k, but
/// |c 10^k| is at most T10.
contract AddSubRoundOnceMaximizeShortShiftTest is Test, AddSubRoundOnceHalmosTest {
    function maximize(int256 c, int256 e) external pure override returns (int256, int256, int256) {
        (int256 m, int256 me,) = LibDecimalFloatImplementation.maximize(c, e);
        return (m / 10, me + 1, 0);
    }

    /// MAX at c = floor(T10 / 1e9): the short form c 10^9 has |c| equal to
    /// floor(T10 / 10^9), so only the strict lower bound of the magnitude
    /// check rejects it.
    function testMaxRejectsAMagnitudeAtT10() external {
        vm.expectRevert(stdError.assertionError);
        // forge-lint: disable-next-line(unsafe-typecast)
        this.check_maximizeFloat(int256(T10 / 1e9), 0, 66);
    }
}
