// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float} from "../../src/lib/LibDecimalFloat.sol";
import {ExponentOverflow, ExponentUnderflow} from "../../src/error/ErrDecimalFloat.sol";
import {PackWrongRangeError} from "./PackWrongRangeError.sol";

/// A range error reverts with a word past the error's two arguments.
contract PackLongError is PackWrongRangeError {
    function rangeError(bool underflow, int256 c, int256 e) internal pure override returns (Float) {
        bytes memory data = abi.encodeWithSelector(
            underflow ? ExponentUnderflow.selector : ExponentOverflow.selector, c, e, uint256(0)
        );
        assembly ("memory-safe") {
            revert(add(data, 0x20), mload(data))
        }
    }
}
