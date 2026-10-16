// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {AddSubRoundOnceHalmosTest} from "./AddSubRoundOnce.halmos.t.sol";

/// `Impl.add` and `maximize` revert.
contract AddSubReverts is AddSubRoundOnceHalmosTest {
    function implAdd(int256, int256, int256, int256) external pure override returns (int256, int256) {
        revert();
    }

    function maximize(int256, int256) external pure override returns (int256, int256, int256) {
        revert();
    }
}
