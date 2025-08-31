// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 thedavidmeister
pragma solidity ^0.8.25;

import {LibDecimalFloat, Float} from "../LibDecimalFloat.sol";

import {LibFixedPointDecimalFormat} from "rain.math.fixedpoint/lib/format/LibFixedPointDecimalFormat.sol";
import {LibDecimalFloatImplementation} from "../../lib/implementation/LibDecimalFloatImplementation.sol";

import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

import {console2} from "forge-std/console2.sol";

library LibFormatDecimalFloat {
    /// Format a decimal float as a string.
    /// Not particularly efficient as it is intended for offchain use that
    /// doesn't cost gas.
    /// @param float The decimal float to format.
    /// @return The string representation of the decimal float.
    function toDecimalString(Float float) internal pure returns (string memory) {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.unpack(float);
        if (signedCoefficient == 0) {
            return "0";
        }

        (int256 coefficientMaximized, int256 exponentMaximized) =
            LibDecimalFloatImplementation.maximize(signedCoefficient, exponent);

        bool isAtLeastE76 = coefficientMaximized / 1e76 != 0;
        uint256 scaleExponent = isAtLeastE76 ? uint256(76) : uint256(75);
        uint256 scale = uint256(10) ** scaleExponent;

        int256 integral = coefficientMaximized / int256(scale);
        int256 fractional = coefficientMaximized % int256(scale);
        // Integral encodes the negativity of the number so don't want to
        // duplicate it here.
        if (fractional < 0) {
            fractional = -fractional;
        }

        while ((fractional / 10) * 10 == fractional) {
            fractional /= 10;
        }

        string memory integralString = Strings.toString(integral);
        string memory fractionalString = Strings.toString(fractional);
        string memory exponentString = (exponentMaximized == 0)
            ? ""
            : string.concat("e", Strings.toString(exponentMaximized + int256(scaleExponent)));

        string memory fullString = string.concat(integralString, ".", fractionalString, exponentString);
        console2.log(fullString, "full string");

        return fullString;
    }
}
