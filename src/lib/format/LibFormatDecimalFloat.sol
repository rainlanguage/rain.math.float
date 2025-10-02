// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibDecimalFloat, Float} from "../LibDecimalFloat.sol";

import {LibDecimalFloatImplementation} from "../../lib/implementation/LibDecimalFloatImplementation.sol";

import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

import {UnformatableExponent} from "../../error/ErrFormat.sol";

library LibFormatDecimalFloat {
    function countSigFigs(int256 signedCoefficient, int256 exponent) internal pure returns (uint256) {
        if (signedCoefficient == 0) {
            return 1;
        }

        uint256 sigFigs = 0;

        if (exponent < 0) {
            while (signedCoefficient % 10 == 0) {
                signedCoefficient /= 10;
                exponent++;
            }
        }

        while (signedCoefficient != 0) {
            sigFigs++;
            signedCoefficient /= 10;
        }

        // Adjust for exponent
        if (exponent < 0) {
            exponent = -exponent;
            // exponent > 0
            // forge-lint: disable-next-line(unsafe-typecast)
            sigFigs = sigFigs > uint256(exponent) ? sigFigs : uint256(exponent);
        } else if (exponent > 0) {
            // exponent > 0
            // forge-lint: disable-next-line(unsafe-typecast)
            sigFigs += uint256(exponent);
        }

        return sigFigs;
    }

    /// Format a decimal float as a string.
    /// Not particularly efficient as it is intended for offchain use that
    /// doesn't cost gas.
    /// @param float The decimal float to format.
    /// @return The string representation of the decimal float.
    //slither-disable-next-line cyclomatic-complexity
    function toDecimalString(Float float, bool scientific) internal pure returns (string memory) {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.unpack(float);
        if (signedCoefficient == 0) {
            return "0";
        }

        // uint256 sigFigs = countSigFigs(signedCoefficient, exponent);
        // bool scientific = sigFigs > sigFigsLimit;
        uint256 scaleExponent;
        uint256 scale = 0;
        if (scientific) {
            (signedCoefficient, exponent) = LibDecimalFloatImplementation.maximizeFull(signedCoefficient, exponent);

            if (signedCoefficient / 1e76 != 0) {
                scaleExponent = 76;
                scale = 1e76;
            } else {
                scaleExponent = 75;
                scale = 1e75;
            }
        } else {
            if (exponent > 0) {
                // exponent > 0
                // forge-lint: disable-next-line(unsafe-typecast)
                signedCoefficient *= int256(10) ** uint256(exponent);
                exponent = 0;
            }
            if (exponent < 0) {
                if (exponent < -76) {
                    revert UnformatableExponent(exponent);
                }
                // negating a signed exponent will always fit in uint256.
                // forge-lint: disable-next-line(unsafe-typecast)
                scale = uint256(10) ** uint256(-exponent);
                // negating a signed exponent will always fit in uint256.
                // forge-lint: disable-next-line(unsafe-typecast)
                scaleExponent = uint256(-exponent);
            } else {
                // exponent is zero here.
                scaleExponent = 0;
            }
        }

        int256 integral = signedCoefficient;
        int256 fractional = int256(0);
        if (scale != 0) {
            // scale is one of two possible values so won't truncate when cast
            // or explicitly has a guard against it truncating.
            // forge-lint: disable-next-line(unsafe-typecast)
            integral = signedCoefficient / int256(scale);
            // scale is one of two possible values so won't truncate when cast
            // or explicitly has a guard against it truncating.
            // forge-lint: disable-next-line(unsafe-typecast)
            fractional = signedCoefficient % int256(scale);
        }

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
                // fracScale being 10x less than scale means it cannot overflow
                // when cast to `int256`.
                // forge-lint: disable-next-line(unsafe-typecast)
                while (fractional / int256(fracScale) == 0) {
                    fracScale /= 10;
                    fracLeadingZeros++;
                }

                for (uint256 i = 0; i < fracLeadingZeros; i++) {
                    fracLeadingZerosString = string.concat(fracLeadingZerosString, "0");
                }

                while (fractional % 10 == 0) {
                    fractional /= 10;
                }
            }

            fractionalString =
                fractional == 0 ? "" : string.concat(".", fracLeadingZerosString, Strings.toString(fractional));
        }

        string memory integralString = Strings.toString(integral);
        // scaleExponent comes from either hardcoded values or `exponent` which
        // is an `int256` that was cast to `uint256` above, which can be cast
        // back to `int256` without truncation.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 displayExponent = exponent + int256(scaleExponent);
        string memory exponentString =
            (displayExponent == 0 || !scientific) ? "" : string.concat("e", Strings.toString(displayExponent));

        string memory prefix = isNeg ? "-" : "";

        string memory fullString = string.concat(prefix, integralString, fractionalString, exponentString);

        return fullString;
    }
}
