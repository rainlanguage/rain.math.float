// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float} from "../../src/lib/LibDecimalFloat.sol";
import {PackWrongRangeError} from "./PackWrongRangeError.sol";

/// A range error returns zero.
contract PackNeverReverts is PackWrongRangeError {
    function rangeError(bool, int256, int256) internal pure override returns (Float) {
        return Float.wrap(0);
    }
}
