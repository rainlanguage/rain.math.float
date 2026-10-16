// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibHalmosExact} from "./LibHalmosExact.sol";

/// Halmos: the hint filters the add/sub lemmas return on are true for every
/// input they are given, so those lemmas exclude nothing by them.
/// `LibHalmosExactHoldsCoverTest.t.sol` checks under forge that every digit
/// count in [0, 76] reaches the filters, and `LibHalmosExactHoldsFalseTest.t.sol`
/// that a filter reporting false fails the lemma.
contract LibHalmosExactHalmosTest {
    function maximizeHintsOf(int256 c, uint256 j) external pure virtual returns (bool) {
        return LibHalmosExact.maximizeHints(c, j);
    }

    function packHintsOf(int256 c, uint256 n) external pure virtual returns (bool) {
        return LibHalmosExact.packHints(c, n);
    }

    function divHintOf(int256 x, int256 d) external pure virtual returns (bool) {
        return LibHalmosExact.divHint(x, d);
    }

    function check_divHintHolds(int256 x) external view {
        assert(this.divHintOf(x, 1e75));
    }

    /// Every nonzero int256 has one digit count j + 1 in [1, 77].
    function check_maximizeHintsHold(int256 c, uint256 jBits) external view {
        uint256 j = LibHalmosExact.concrete(jBits, 7);
        if (j > 76 || !LibHalmosExact.inSlice(j)) return;
        uint256 x = LibHalmosExact.abs(c);
        if (x < 10 ** j || x >= 10 ** (j + 1)) return;
        assert(this.maximizeHintsOf(c, j));
    }

    /// Every nonzero int256 has one digit count n + 1 in [1, 77].
    function check_packHintsHold(int256 c, uint256 nBits) external view {
        uint256 n = LibHalmosExact.concrete(nBits, 7);
        if (n > 76 || !LibHalmosExact.inSlice(n) || !LibHalmosExact.hasDigits(c, n)) return;
        assert(this.packHintsOf(c, n));
    }
}
