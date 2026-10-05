// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation, POW_FIXED_ONE} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

contract LibDecimalFloatImplementationExp10FixedTest is Test {
    function assertNear(uint256 actual, uint256 expected, uint256 ulps) internal pure {
        uint256 diff = actual > expected ? actual - expected : expected - actual;
        assertLe(diff, ulps, "near");
    }

    /// References are 10^x to 50 places from `bc -l` at scale 200.
    function testExp10Fixed() external pure {
        assertEq(LibDecimalFloatImplementation.exp10Fixed(0), POW_FIXED_ONE);
        assertNear(LibDecimalFloatImplementation.exp10Fixed(POW_FIXED_ONE), 10 * POW_FIXED_ONE, 5e4);
        assertNear(
            LibDecimalFloatImplementation.exp10Fixed(5e49), 316227766016837933199889354443271853371955513932521, 5e4
        );
        assertNear(
            LibDecimalFloatImplementation.exp10Fixed(1e47), 100230523807789967191540488932811055405366845354216, 5e4
        );
        assertNear(LibDecimalFloatImplementation.exp10Fixed(1), POW_FIXED_ONE, 1);
    }
}
