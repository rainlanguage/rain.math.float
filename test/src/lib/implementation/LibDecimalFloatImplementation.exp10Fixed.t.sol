// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation, POW_FIXED_ONE} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";

contract LibDecimalFloatImplementationExp10FixedTest is Test {
    /// The true power is in [truncated, truncated + 1), and exp10Fixed is
    /// within [-5.1637e-47, 5.2e-51] relative of it.
    function assertProvenBound(uint256 actual, uint256 truncated) internal pure {
        uint256 below = Math.mulDiv(truncated + 1, 51637, 1e51, Math.Rounding.Ceil);
        uint256 above = Math.mulDiv(truncated + 1, 52, 1e52, Math.Rounding.Ceil);
        assertGe(actual + below, truncated, "below");
        assertLe(actual, truncated + 1 + above, "above");
    }

    /// References are 10^x truncated to 50 places from `bc -l` at scale 200.
    function testExp10Fixed() external pure {
        assertEq(LibDecimalFloatImplementation.exp10Fixed(0), POW_FIXED_ONE);
        assertProvenBound(LibDecimalFloatImplementation.exp10Fixed(POW_FIXED_ONE), 10 * POW_FIXED_ONE);
        assertProvenBound(LibDecimalFloatImplementation.exp10Fixed(5e49), 316227766016837933199889354443271853371955513932521);
        assertProvenBound(LibDecimalFloatImplementation.exp10Fixed(1e47), 100230523807789967191540488932811055405366845354216);
        assertProvenBound(LibDecimalFloatImplementation.exp10Fixed(1), 100000000000000000000000000000000000000000000000002);
    }
}
