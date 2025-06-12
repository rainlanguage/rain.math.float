// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Float} from "src/lib/LibDecimalFloat.sol";

// Helper functions only for usage in tests
function F(uint256 x) pure returns (Float) {
    return Float.wrap(bytes32(x));
}