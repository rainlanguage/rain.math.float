// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {stdError} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {SeriesSolidityEquivalenceHalmosTest} from "./SeriesSolidityEquivalence.halmos.t.sol";

/// The Solidity series one above the assembly.
contract SeriesSolidityEquivalenceSolAboveTest is SeriesSolidityEquivalenceHalmosTest {
    function log10RatioSol(uint256 a, uint256 b, bool relative) external pure override returns (int256, int256) {
        (int256 c, int256 e) = LibDecimalFloatImplementation.log10Ratio(a, b, relative);
        return (c + 1, e);
    }

    function exp10FixedSol(uint256 x) external pure override returns (uint256) {
        return LibDecimalFloatImplementation.exp10Fixed(x) + 1;
    }

    function testLog10RatioRejectsAChangedCoefficient() external {
        vm.expectRevert(stdError.assertionError);
        this.check_log10RatioEquivalence(10001, 10000, false);
    }

    function testExp10FixedRejectsAChangedResult() external {
        vm.expectRevert(stdError.assertionError);
        this.check_exp10FixedEquivalence(1e49);
    }
}
