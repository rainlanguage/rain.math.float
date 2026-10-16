// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float} from "../../src/lib/LibDecimalFloat.sol";
import {AgreeToleranceNegative} from "../../src/error/ErrDecimalFloat.sol";
import {AgreeHalmosTest} from "./Agree.halmos.t.sol";

/// `agree` returns the revert data's shape instead of reverting.
contract AgreeReturns is AgreeHalmosTest {
    function agree(Float absolute, Float proportional, Float, Float) external pure override returns (bool) {
        bytes memory data = abi.encodeWithSelector(AgreeToleranceNegative.selector, absolute, proportional);
        assembly ("memory-safe") {
            return(add(data, 0x20), mload(data))
        }
    }
}
