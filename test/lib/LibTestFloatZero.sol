// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Float} from "src/lib/LibDecimalFloat.sol";

/// A zero Float at exponent `e`, with the exponent in the high 32 bits:
/// `packLossless(0, e)` would already be `FLOAT_ZERO`.
/// @param e The exponent to place.
/// @return The zero Float carrying `e`.
function zeroAt(int32 e) pure returns (Float) {
    // The exponent's two's complement bits, as packing places them.
    // forge-lint: disable-next-line(unsafe-typecast)
    return Float.wrap(bytes32(uint256(uint32(e)) << 224));
}
