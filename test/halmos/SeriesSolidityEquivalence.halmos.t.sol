// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibDecimalFloatImplementationSeriesSolidity} from "../lib/LibDecimalFloatImplementationSeriesSolidity.sol";

/// Halmos: the assembly `log10Ratio` and `exp10Fixed` (#352) return and revert
/// exactly as their plain-Solidity copies, for every input.
///
/// Neither lemma is proved under CI's 5-minute limit per run, so neither is in
/// its matrix: #515 (`log10Ratio`) and #516 (`exp10Fixed`).
contract SeriesSolidityEquivalenceHalmosTest is Test {
    function log10RatioAsm(uint256 a, uint256 b, bool relative) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.log10Ratio(a, b, relative);
    }

    function log10RatioSol(uint256 a, uint256 b, bool relative) external pure returns (int256, int256) {
        return LibDecimalFloatImplementationSeriesSolidity.log10Ratio(a, b, relative);
    }

    function exp10FixedAsm(uint256 x) external pure returns (uint256) {
        return LibDecimalFloatImplementation.exp10Fixed(x);
    }

    function exp10FixedSol(uint256 x) external pure returns (uint256) {
        return LibDecimalFloatImplementationSeriesSolidity.exp10Fixed(x);
    }

    function assertSameOutcome(bytes memory callAsm, bytes memory callSol) internal view {
        (bool okAsm, bytes memory outAsm) = address(this).staticcall(callAsm);
        (bool okSol, bytes memory outSol) = address(this).staticcall(callSol);
        assert(okAsm == okSol);
        assert(outAsm.length == outSol.length);
        for (uint256 i = 0; i < outAsm.length; i++) {
            assert(outAsm[i] == outSol[i]);
        }
    }

    /// Unproven under the 5-minute limit, not in the CI matrix: see #515.
    function check_log10RatioEquivalence(uint256 a, uint256 b, bool relative) external view {
        assertSameOutcome(
            abi.encodeCall(this.log10RatioAsm, (a, b, relative)), abi.encodeCall(this.log10RatioSol, (a, b, relative))
        );
    }

    /// Unproven under the 5-minute limit, not in the CI matrix: see #516.
    function check_exp10FixedEquivalence(uint256 x) external view {
        assertSameOutcome(abi.encodeCall(this.exp10FixedAsm, (x)), abi.encodeCall(this.exp10FixedSol, (x)));
    }
}
