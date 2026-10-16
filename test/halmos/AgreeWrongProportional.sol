// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float} from "../../src/lib/LibDecimalFloat.sol";
import {AgreeToleranceNegative} from "../../src/error/ErrDecimalFloat.sol";
import {AgreeHalmosTest} from "./Agree.halmos.t.sol";

/// `agree` reports the absolute tolerance in the proportional's place.
contract AgreeWrongProportional is AgreeHalmosTest {
    function agree(Float absolute, Float, Float, Float) external pure override returns (bool) {
        revert AgreeToleranceNegative(absolute, absolute);
    }
}
