// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 thedavidmeister
pragma solidity ^0.8.25;

import {LibDecimalFloat, Float} from "../LibDecimalFloat.sol";

import {LibFixedPointDecimalFormat} from "rain.math.fixedpoint/lib/format/LibFixedPointDecimalFormat.sol";

library LibFormatDecimalFloat {
    /// Format a decimal float as a string.
    /// Currently is a thin wrapper around converting to a fixed point decimal
    /// and then formatting that as a string.
    /// In the future this may be extended to support a wider range of possible
    /// values.
    /// @param signedCoefficient The signed coefficient of the decimal float.
    /// @param exponent The exponent of the decimal float.
    /// @return The string representation of the decimal float.
    function toDecimalString(int256 signedCoefficient, int256 exponent) internal pure returns (string memory) {
        string memory prefix = "";
        if (signedCoefficient < 0) {
            prefix = "-";
            signedCoefficient = -signedCoefficient;
        }
        uint256 decimal18Value = LibDecimalFloat.toFixedDecimalLossless(signedCoefficient, exponent, 18);
        return string.concat(prefix, LibFixedPointDecimalFormat.fixedPointToDecimalString(decimal18Value));
    }

    function toDecimalString(Float float) internal pure returns (string memory) {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.unpack(float);
        return toDecimalString(signedCoefficient, exponent);
    }
}
