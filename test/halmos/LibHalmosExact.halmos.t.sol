// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibHalmosExact} from "./LibHalmosExact.sol";

/// Halmos: the hint filters the add/sub lemmas return on are true for every
/// input they are given, so those lemmas exclude nothing by them.
contract LibHalmosExactHalmosTest {
    function check_divHintHolds(int256 x) external pure {
        assert(LibHalmosExact.divHint(x, 1e75));
    }

    /// Every nonzero int256 has one digit count j + 1 in [1, 77].
    function check_maximizeHintsHold(int256 c, uint256 jBits) external view {
        uint256 j = LibHalmosExact.concrete(jBits, 7);
        if (j > 76 || !LibHalmosExact.inSlice(j)) return;
        uint256 x = LibHalmosExact.abs(c);
        if (x < 10 ** j || x >= 10 ** (j + 1)) return;
        assert(LibHalmosExact.maximizeHints(c, j));
    }

    /// Every nonzero int256 has one digit count n + 1 in [1, 77].
    function check_packHintsHold(int256 c, uint256 nBits) external view {
        uint256 n = LibHalmosExact.concrete(nBits, 7);
        if (n > 76 || !LibHalmosExact.inSlice(n) || !LibHalmosExact.hasDigits(c, n)) return;
        assert(LibHalmosExact.packHints(c, n));
    }
}
