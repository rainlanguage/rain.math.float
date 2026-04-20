// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibDecimalFloat, Float} from "../LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "../implementation/LibDecimalFloatImplementation.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {UnformatableExponent} from "../../error/ErrFormat.sol";

/// @dev Library for formatting DecimalFloat values as strings.
/// Not particularly efficient as it is intended for offchain use that doesn't
/// cost gas.
library LibFormatDecimalFloat {
    /// Maximum `|exponent|` supported by non-scientific formatting. Exponents
    /// outside `[-MAX_NON_SCIENTIFIC_EXPONENT, MAX_NON_SCIENTIFIC_EXPONENT]`
    /// revert with `UnformatableExponent`. The cap exists to prevent unbounded
    /// memory use when building the output string; callers that need to render
    /// such values should use scientific mode.
    int256 internal constant MAX_NON_SCIENTIFIC_EXPONENT = 1000;

    /// Format a decimal float as a string.
    /// Not particularly efficient as it is intended for offchain use that
    /// doesn't cost gas.
    /// @param float The decimal float to format.
    /// @param scientific Whether to format in scientific notation (e.g. 1e10).
    /// @return The string representation of the decimal float.
    function toDecimalString(Float float, bool scientific) internal pure returns (string memory) {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.unpack(float);
        if (signedCoefficient == 0) {
            return "0";
        }
        if (scientific) {
            return _toScientific(signedCoefficient, exponent);
        }
        return _toNonScientific(signedCoefficient, exponent);
    }

    /// Scientific notation: render as `d.dddeN` where the leading digit is the
    /// most significant digit of the maximized coefficient. Uses big-integer
    /// division to place the decimal point; the divisor is always `1e75` or
    /// `1e76` which both fit in int256.
    function _toScientific(int256 signedCoefficient, int256 exponent) private pure returns (string memory) {
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.maximizeFull(signedCoefficient, exponent);

        uint256 scale;
        uint256 scaleExponent;
        if (signedCoefficient / 1e76 != 0) {
            scaleExponent = 76;
            scale = 1e76;
        } else {
            scaleExponent = 75;
            scale = 1e75;
        }

        // scale is one of two hardcoded values (1e76, 1e75), both fit int256.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 integral = signedCoefficient / int256(scale);
        // scale is one of two hardcoded values (1e76, 1e75), both fit int256.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 fractional = signedCoefficient % int256(scale);

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
        if (fractional != 0) {
            uint256 fracLeadingZeros = 0;
            uint256 fracScale = scale / 10;
            // fracScale is scale/10 of a hardcoded power of 10, fits int256.
            // forge-lint: disable-next-line(unsafe-typecast)
            while (fractional / int256(fracScale) == 0) {
                fracScale /= 10;
                fracLeadingZeros++;
            }

            string memory fracLeadingZerosString = "";
            for (uint256 i = 0; i < fracLeadingZeros; i++) {
                fracLeadingZerosString = string.concat(fracLeadingZerosString, "0");
            }

            while (fractional % 10 == 0) {
                fractional /= 10;
            }

            fractionalString = string.concat(".", fracLeadingZerosString, Strings.toStringSigned(fractional));
        }

        string memory integralString = Strings.toStringSigned(integral);
        // scaleExponent is a hardcoded small value (75 or 76); the cast back
        // to int256 cannot truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 displayExponent = exponent + int256(scaleExponent);
        string memory exponentString =
            displayExponent == 0 ? "" : string.concat("e", Strings.toStringSigned(displayExponent));
        string memory prefix = isNeg ? "-" : "";
        return string.concat(prefix, integralString, fractionalString, exponentString);
    }

    /// Non-scientific notation: render by placing a decimal point inside the
    /// coefficient's digit string according to the exponent. Does not compute
    /// `10^exponent` as an integer, so the output is valid for any
    /// `|exponent| <= MAX_NON_SCIENTIFIC_EXPONENT` — including exponents below
    /// `-76` that arise from near-cancellation add/sub.
    function _toNonScientific(int256 signedCoefficient, int256 exponent) private pure returns (string memory) {
        if (exponent > MAX_NON_SCIENTIFIC_EXPONENT || exponent < -MAX_NON_SCIENTIFIC_EXPONENT) {
            revert UnformatableExponent(exponent);
        }

        bool isNeg = signedCoefficient < 0;
        uint256 absCoef;
        if (isNeg) {
            // signedCoefficient came from `unpack` so |signedCoefficient| fits
            // int224; negation always fits uint256.
            // forge-lint: disable-next-line(unsafe-typecast)
            absCoef = uint256(-signedCoefficient);
        } else {
            // signedCoefficient is non-negative and fits int224, so fits
            // uint256.
            // forge-lint: disable-next-line(unsafe-typecast)
            absCoef = uint256(signedCoefficient);
        }

        bytes memory digits = bytes(Strings.toString(absCoef));
        uint256 k = digits.length;

        // Strip trailing decimal zeros of the coefficient, raising the
        // exponent by the same count. Value-preserving, and simplifies
        // downstream cases by eliminating redundant zeros.
        uint256 trailingZeros = 0;
        while (trailingZeros < k && digits[k - 1 - trailingZeros] == "0") {
            trailingZeros++;
        }
        uint256 sigK = k - trailingZeros;
        // k <= 78 (int224 max has ~68 decimal digits), so int256(trailingZeros)
        // cannot overflow.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 effExp = exponent + int256(trailingZeros);

        string memory prefix = isNeg ? "-" : "";

        if (effExp >= 0) {
            // Significant digits followed by `effExp` trailing zeros.
            // effExp is bounded by MAX_NON_SCIENTIFIC_EXPONENT + ~78.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 uEffExp = uint256(effExp);
            bytes memory out = new bytes(sigK + uEffExp);
            for (uint256 i = 0; i < sigK; i++) {
                out[i] = digits[i];
            }
            for (uint256 i = 0; i < uEffExp; i++) {
                out[sigK + i] = "0";
            }
            return string.concat(prefix, string(out));
        }

        // effExp < 0
        // effExp >= -MAX_NON_SCIENTIFIC_EXPONENT (by the guard above) so
        // -effExp is positive and fits uint256.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 absEffExp = uint256(-effExp);

        if (sigK > absEffExp) {
            // Decimal point sits inside the significant digits.
            uint256 splitAt = sigK - absEffExp;
            bytes memory out = new bytes(sigK + 1);
            for (uint256 i = 0; i < splitAt; i++) {
                out[i] = digits[i];
            }
            out[splitAt] = ".";
            for (uint256 i = 0; i < absEffExp; i++) {
                out[splitAt + 1 + i] = digits[splitAt + i];
            }
            return string.concat(prefix, string(out));
        } else {
            // "0." + (absEffExp - sigK) leading zeros + significant digits.
            uint256 leadingZerosCount = absEffExp - sigK;
            bytes memory out = new bytes(2 + leadingZerosCount + sigK);
            out[0] = "0";
            out[1] = ".";
            for (uint256 i = 0; i < leadingZerosCount; i++) {
                out[2 + i] = "0";
            }
            for (uint256 i = 0; i < sigK; i++) {
                out[2 + leadingZerosCount + i] = digits[i];
            }
            return string.concat(prefix, string(out));
        }
    }
}
