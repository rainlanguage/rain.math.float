// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float} from "../../src/lib/LibDecimalFloat.sol";
import {AgreeToleranceNegative} from "../../src/error/ErrDecimalFloat.sol";
import {AgreeHalmosTest} from "./Agree.halmos.t.sol";

/// `agree` reports the proportional tolerance in the absolute's place.
contract AgreeWrongAbsolute is AgreeHalmosTest {
    function agree(Float, Float proportional, Float, Float) external pure override returns (bool) {
        revert AgreeToleranceNegative(proportional, proportional);
    }
}
