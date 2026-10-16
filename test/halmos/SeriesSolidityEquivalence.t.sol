// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {SeriesSolidityEquivalenceHalmosTest} from "./SeriesSolidityEquivalence.halmos.t.sol";

/// Forge checks on `SeriesSolidityEquivalence.halmos.t.sol`, whose lemmas
/// have no filter and are not in the CI matrix (#515, #516): each at the ends
/// of its input.
contract SeriesSolidityEquivalenceCoverTest is SeriesSolidityEquivalenceHalmosTest {
    /// `exp10Fixed` at zero, one below `POW_FIXED_ONE`, at it (both revert
    /// `Exp10FixedOutOfRange`) and at uint256.max.
    function testExp10FixedAtItsEdges() external view {
        this.check_exp10FixedEquivalence(0);
        this.check_exp10FixedEquivalence(1e50 - 1);
        this.check_exp10FixedEquivalence(1e50);
        this.check_exp10FixedEquivalence(type(uint256).max);
    }

    /// `log10Ratio` over every pair of zero, one, `POW_FIXED_ONE` and
    /// uint256.max, both values of relative: equal operands, a zero operand,
    /// and sums that wrap, every one a revert in both. Then ratios inside the
    /// series' range in both orders: 10001 : 10000, and the same ratio at the
    /// 1e50 scale `relative` needs.
    function testLog10RatioAtItsEdges() external view {
        uint256[4] memory xs = [uint256(0), 1, 1e50, type(uint256).max];
        for (uint256 a = 0; a < xs.length; a++) {
            for (uint256 b = 0; b < xs.length; b++) {
                this.check_log10RatioEquivalence(xs[a], xs[b], false);
                this.check_log10RatioEquivalence(xs[a], xs[b], true);
            }
        }
        this.check_log10RatioEquivalence(10001, 10000, false);
        this.check_log10RatioEquivalence(10000, 10001, false);
        this.check_log10RatioEquivalence(1e50 + 1e46, 1e50, true);
        this.check_log10RatioEquivalence(1e50, 1e50 + 1e46, true);
    }
}
