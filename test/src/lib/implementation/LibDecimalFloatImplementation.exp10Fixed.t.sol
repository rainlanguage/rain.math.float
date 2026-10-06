// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation, POW_FIXED_ONE} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";

contract LibDecimalFloatImplementationExp10FixedTest is Test {
    /// The true power is in [truncated, truncated + 1), and exp10Fixed is
    /// within [-3.048e-49, 0] relative of it, so at most truncated.
    function assertProvenBound(uint256 actual, uint256 truncated) internal pure {
        uint256 below = Math.mulDiv(truncated + 1, 3048, 1e52, Math.Rounding.Ceil);
        assertGe(actual + below, truncated, "below");
        assertLe(actual, truncated, "above");
    }

    /// References are 10^x truncated to 50 places from `bc -l` at scale 120.
    function testExp10Fixed() external pure {
        assertEq(LibDecimalFloatImplementation.exp10Fixed(0), POW_FIXED_ONE);
        // Every binary digit and the largest remainder.
        assertProvenBound(
            LibDecimalFloatImplementation.exp10Fixed(POW_FIXED_ONE - 1),
            999999999999999999999999999999999999999999999999976
        );
        assertProvenBound(
            LibDecimalFloatImplementation.exp10Fixed(5e49), 316227766016837933199889354443271853371955513932521
        );
        assertProvenBound(
            LibDecimalFloatImplementation.exp10Fixed(7.5e49), 562341325190349080394951039776481231468251043098691
        );
        assertProvenBound(
            LibDecimalFloatImplementation.exp10Fixed(12345678901234567890123456789012345678901234567890),
            132879133982907133325799753963302210145286380241964
        );
        // The remainder alone, at its largest.
        assertProvenBound(
            LibDecimalFloatImplementation.exp10Fixed(1.52587890625e45 - 1),
            100003513527746185660858233586155663318996214797052
        );
        assertProvenBound(
            LibDecimalFloatImplementation.exp10Fixed(1e47), 100230523807789967191540488932811055405366845354216
        );
        assertProvenBound(
            LibDecimalFloatImplementation.exp10Fixed(1), 100000000000000000000000000000000000000000000000002
        );
    }
}
