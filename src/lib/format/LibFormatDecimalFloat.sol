// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 thedavidmeister
pragma solidity ^0.8.25;

import {LibDecimalFloat, Float} from "../LibDecimalFloat.sol";

import {LibFixedPointDecimalFormat} from "rain.math.fixedpoint/lib/format/LibFixedPointDecimalFormat.sol";
import {LibDecimalFloatImplementation} from "../../lib/implementation/LibDecimalFloatImplementation.sol";

import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

library LibFormatDecimalFloat {
    uint256 constant DEFAULT_SIG_FIGS = 9;

    function countSigFigs(int256 signedCoefficient, int256 exponent) internal pure returns (uint256) {
        if (signedCoefficient == 0) {
            return 1;
        }

        uint256 absCoefficient = uint256(signedCoefficient < 0 ? -signedCoefficient : signedCoefficient);
        uint256 sigFigs = 0;

        if (exponent < 0) {
            while (absCoefficient / 10 * 10 == absCoefficient) {
                absCoefficient /= 10;
                exponent++;
            }
        }

        while (absCoefficient != 0) {
            sigFigs++;
            absCoefficient /= 10;
        }

        // Adjust for exponent
        if (exponent < 0) {
            exponent = -exponent;
            sigFigs = sigFigs > uint256(exponent) ? sigFigs : uint256(exponent);
        } else if (exponent > 0) {
            sigFigs += uint256(exponent);
        }

        return sigFigs;
    }

    /// Overloaded `toDecimalString` with default sig figs.
    function toDecimalString(Float float) internal pure returns (string memory) {
        return toDecimalString(float, DEFAULT_SIG_FIGS);
    }

    /// Format a decimal float as a string.
    /// Not particularly efficient as it is intended for offchain use that
    /// doesn't cost gas.
    /// @param float The decimal float to format.
    /// @return The string representation of the decimal float.
    function toDecimalString(Float float, uint256 sigFigsLimit) internal pure returns (string memory) {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.unpack(float);
        if (signedCoefficient == 0) {
            return "0";
        }

        uint256 sigFigs = countSigFigs(signedCoefficient, exponent);
        bool scientific = sigFigs > sigFigsLimit;
        uint256 scaleExponent;
        uint256 scale;
        if (scientific) {
            (signedCoefficient, exponent) = LibDecimalFloatImplementation.maximize(signedCoefficient, exponent);

            bool isAtLeastE76 = signedCoefficient / 1e76 != 0;
            scaleExponent = isAtLeastE76 ? uint256(76) : uint256(75);
            scale = uint256(10) ** scaleExponent;
        } else {
            if (exponent > 0) {
                signedCoefficient *= int256(10) ** uint256(exponent);
                exponent = 0;
            }
            if (exponent < 0) {
                scale = uint256(10) ** uint256(-exponent);
            }
            scaleExponent = uint256(exponent);
        }

        int256 integral = scale != 0 ? signedCoefficient / int256(scale) : signedCoefficient;
        int256 fractional = scale != 0 ? signedCoefficient % int256(scale) : int256(0);
        bool isNeg = false;
        if (integral < 0) {
            isNeg = true;
            integral = -integral;
        }
        if (fractional < 0) {
            isNeg = true;
            fractional = -fractional;
        }

        string memory fractionalString = "";
        {
            string memory fracLeadingZerosString = "";

            if (fractional != 0) {
                uint256 fracLeadingZeros = 0;
                uint256 fracScale = scale / 10;
                while (fractional / int256(fracScale) == 0) {
                    fracScale /= 10;
                    fracLeadingZeros++;
                }

                for (uint256 i = 0; i < fracLeadingZeros; i++) {
                    fracLeadingZerosString = string.concat(fracLeadingZerosString, "0");
                }

                while ((fractional / 10) * 10 == fractional) {
                    fractional /= 10;
                }
            }

            fractionalString =
                fractional == 0 ? "" : string.concat(".", fracLeadingZerosString, Strings.toString(fractional));
        }

        string memory integralString = Strings.toString(integral);

        int256 displayExponent = exponent + int256(scaleExponent);
        string memory exponentString =
            (displayExponent == 0 || !scientific) ? "" : string.concat("e", Strings.toString(displayExponent));

        string memory prefix = isNeg ? "-" : "";

        string memory fullString = string.concat(prefix, integralString, fractionalString, exponentString);

        return fullString;
    }
}
