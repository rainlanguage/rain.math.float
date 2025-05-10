// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "../lib/LibDecimalFloat.sol";

contract DecimalFloat {
    using LibDecimalFloat for Float;

    function mul(Float a, Float b) external pure returns (Float) {
        return a.mul(b);
    }
}
