// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Float} from "../../src/lib/LibDecimalFloat.sol";

/// Zero Floats that carry an exponent, which no packing produces.
library LibTestFloatZero {
    /// A zero Float at `exponent`, with the exponent in the high 32 bits:
    /// `packLossless(0, exponent)` would already be `FLOAT_ZERO`.
    /// @param exponent The exponent to place.
    /// @return The zero Float carrying `exponent`.
    function zeroAt(int32 exponent) internal pure returns (Float) {
        // The exponent's two's complement bits, as packing places them.
        // forge-lint: disable-next-line(unsafe-typecast)
        return Float.wrap(bytes32(uint256(uint32(exponent)) << 224));
    }
}
