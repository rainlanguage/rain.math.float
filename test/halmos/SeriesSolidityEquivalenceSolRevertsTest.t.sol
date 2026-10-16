// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {stdError} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {SeriesSolidityEquivalenceHalmosTest} from "./SeriesSolidityEquivalence.halmos.t.sol";

/// The Solidity series reverting with the bytes the assembly returns: the two
/// outcomes differ only in the success flag.
contract SeriesSolidityEquivalenceSolRevertsTest is SeriesSolidityEquivalenceHalmosTest {
    function log10RatioSol(uint256 a, uint256 b, bool relative) external pure override returns (int256, int256) {
        (int256 c, int256 e) = LibDecimalFloatImplementation.log10Ratio(a, b, relative);
        bytes memory data = abi.encode(c, e);
        assembly ("memory-safe") {
            revert(add(data, 0x20), mload(data))
        }
    }

    function exp10FixedSol(uint256 x) external pure override returns (uint256) {
        uint256 result = LibDecimalFloatImplementation.exp10Fixed(x);
        assembly ("memory-safe") {
            mstore(0, result)
            revert(0, 0x20)
        }
    }

    function testLog10RatioRejectsADifferentOutcome() external {
        vm.expectRevert(stdError.assertionError);
        this.check_log10RatioEquivalence(10001, 10000, false);
    }

    function testExp10FixedRejectsADifferentOutcome() external {
        vm.expectRevert(stdError.assertionError);
        this.check_exp10FixedEquivalence(1e49);
    }
}
