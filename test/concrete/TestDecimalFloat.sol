// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

/// Additional exposed functions for testing the internals of floats
/// from downstream environments, e.g. rust.
contract TestDecimalFloat {
    using LibDecimalFloat for Float;

    /// Exposes `LibDecimalFloat.packLossless` for offchain use.
    /// @param coefficient The coefficient to pack.
    /// @param exponent The exponent to pack.
    /// @return The packed float.
    function packLossless(int224 coefficient, int32 exponent) external pure returns (Float) {
        return LibDecimalFloat.packLossless(coefficient, exponent);
    }

    /// Exposes `LibDecimalFloat.unpack` for offchain use.
    /// @param float The float to unpack.
    /// @return coefficient The coefficient of the float.
    /// @return exponent The exponent of the float.
    function unpack(Float float) external pure returns (int256, int256) {
        return LibDecimalFloat.unpack(float);
    }
}
