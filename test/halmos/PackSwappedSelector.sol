// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float} from "../../src/lib/LibDecimalFloat.sol";
import {ExponentOverflow, ExponentUnderflow} from "../../src/error/ErrDecimalFloat.sol";
import {PackWrongRangeError} from "./PackWrongRangeError.sol";

/// A range error reverts with the other error.
contract PackSwappedSelector is PackWrongRangeError {
    function rangeError(bool underflow, int256 c, int256 e) internal pure override returns (Float) {
        if (underflow) revert ExponentOverflow(c, e);
        revert ExponentUnderflow(c, e);
    }
}
