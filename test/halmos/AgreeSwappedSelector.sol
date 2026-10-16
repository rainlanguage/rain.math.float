// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float} from "../../src/lib/LibDecimalFloat.sol";
import {AgreeToleranceNegative, AgreeNoPositiveTolerance} from "../../src/error/ErrDecimalFloat.sol";
import {AgreeHalmosTest} from "./Agree.halmos.t.sol";

/// `agree` reverts with the other class's error.
contract AgreeSwappedSelector is AgreeHalmosTest {
    function agree(Float absolute, Float proportional, Float, Float) external pure override returns (bool) {
        if (coefficient(Float.unwrap(absolute)) < 0 || coefficient(Float.unwrap(proportional)) < 0) {
            revert AgreeNoPositiveTolerance(absolute, proportional);
        }
        revert AgreeToleranceNegative(absolute, proportional);
    }
}
