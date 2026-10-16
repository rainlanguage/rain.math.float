// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {stdError} from "forge-std-1.17.0/src/Test.sol";
import {SeriesSolidityEquivalenceHalmosTest} from "./SeriesSolidityEquivalence.halmos.t.sol";

/// The Solidity series returning nothing where the assembly returns a word.
contract SeriesSolidityEquivalenceSolEmptyTest is SeriesSolidityEquivalenceHalmosTest {
    function log10RatioSol(uint256, uint256, bool) external pure override returns (int256, int256) {
        assembly ("memory-safe") {
            return(0, 0)
        }
    }

    function exp10FixedSol(uint256) external pure override returns (uint256) {
        assembly ("memory-safe") {
            return(0, 0)
        }
    }

    function testLog10RatioRejectsAShorterEncoding() external {
        vm.expectRevert(stdError.assertionError);
        this.check_log10RatioEquivalence(10001, 10000, false);
    }

    function testExp10FixedRejectsAShorterEncoding() external {
        vm.expectRevert(stdError.assertionError);
        this.check_exp10FixedEquivalence(1e49);
    }
}
