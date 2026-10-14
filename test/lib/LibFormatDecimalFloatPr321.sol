// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Float} from "../../src/lib/LibDecimalFloat.sol";
import {
    MAXIMIZED_ZERO_SIGNED_COEFFICIENT,
    MAXIMIZED_ZERO_EXPONENT
} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {MaximizeOverflow} from "../../src/error/ErrDecimalFloat.sol";
import {Strings} from "@openzeppelin-contracts-5.7.0/utils/Strings.sol";
import {UnformatableExponent} from "../../src/error/ErrFormat.sol";

/// `LibFormatDecimalFloat` verbatim from
/// `src/lib/format/LibFormatDecimalFloat.sol` at ce55522 (#321), before #310's
/// format change, with `LibDecimalFloat.unpack` and
/// `LibDecimalFloatImplementation.maximizeFull`, `maximize` and their constants
/// copied from the same commit as private functions, so it calls nothing on
/// the live library. Equivalence tests only.
/// EQUIVALENCE BASELINE ONLY, NEVER A VALUE ORACLE: agreeing with it says
/// nothing about a value. Expected strings come from `expectedFormat` in
/// `LibFormatDecimalFloat.toDecimalString.t.sol`.
library LibFormatDecimalFloatPr321 {
    /// Inline assembly takes only literal constants.
    uint256 private constant E10 = 1e10;
    uint256 private constant E19 = 1e19;
    uint256 private constant E38 = 1e38;
    uint256 private constant E57 = 1e57;
    uint256 private constant E66 = 1e66;
    uint256 private constant E74 = 1e74;
    uint256 private constant E75 = 1e75;
    /// `type(int256).max / 10`. A coefficient times ten fits int256 iff its
    /// magnitude is at most this.
    uint256 private constant TIMES_TEN_MAX =
        5789604461865809771178549250434395392663499233282028201972879200395656481996;
    /// `2 * TIMES_TEN_MAX + 1`.
    uint256 private constant TIMES_TEN_SPAN =
        11579208923731619542357098500868790785326998466564056403945758400791312963993;

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
        (int256 signedCoefficient, int256 exponent) = unpack(float);
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
        int256 originalExponent = exponent;
        (signedCoefficient, exponent) = maximizeFull(signedCoefficient, exponent);

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
        // The parser reconstructs this float by calling packLossless with the
        // display exponent cast to int32. Guard here so the formatter reverts
        // cleanly rather than silently producing a string whose exponent cannot
        // be represented in int32. Both sides are checked: maximizeFull reduces
        // the stored exponent by the digit-count delta (up to ~10 for an
        // int224 coefficient), so displayExponent can be up to ~76 above the
        // original exponent.
        if (displayExponent > type(int32).max || displayExponent < type(int32).min) {
            revert UnformatableExponent(originalExponent);
        }
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
    //slither-disable-next-line cyclomatic-complexity
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

        // When exponent > 0 the formatted integer is absCoef × 10^exponent,
        // which must fit in int224 for the parser to reconstruct the value
        // losslessly. For exponent ≥ 68, 10^68 > int224.max (≈1.34e67) so
        // even coefficient 1 overflows. Otherwise divide int224.max by
        // 10^exponent and check that absCoef doesn't exceed the quotient.
        if (exponent > 0) {
            // exponent > 0, so the cast to uint256 is safe.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 uExp = uint256(exponent);
            if (uExp >= 68) {
                revert UnformatableExponent(exponent);
            }
            uint256 limit = uint256(int256(type(int224).max));
            for (uint256 i = 0; i < uExp; i++) {
                limit /= 10;
            }
            if (absCoef > limit) {
                revert UnformatableExponent(exponent);
            }
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

    /// Unpack a packed bytes32 into a signed coefficient and exponent. This is
    /// the inverse of `pack`.
    /// @param float The packed representation of the signed coefficient and
    /// exponent.
    /// @return signedCoefficient The signed coefficient of the floating point
    /// representation.
    /// @return exponent The exponent of the floating point representation.
    function unpack(Float float) private pure returns (int256 signedCoefficient, int256 exponent) {
        uint256 mask = type(uint224).max;
        assembly ("memory-safe") {
            signedCoefficient := signextend(27, and(float, mask))
            exponent := sar(0xe0, float)
        }
    }

    /// Maximizes a float as per `maximize` but errors if the exponent cannot
    /// take the whole shift. This is analogous to other functions in the lib
    /// that are "lossless".
    /// @param signedCoefficient The signed coefficient.
    /// @param exponent The exponent.
    /// @return signedCoefficient The maximized signed coefficient.
    /// @return exponent The maximized exponent.
    function maximizeFull(int256 signedCoefficient, int256 exponent) private pure returns (int256, int256) {
        (int256 trySignedCoefficient, int256 tryExponent, int256 shortfall) = maximize(signedCoefficient, exponent);
        if (shortfall != 0) {
            revert MaximizeOverflow(signedCoefficient, exponent);
        }
        return (trySignedCoefficient, tryExponent);
    }

    /// Maximizes a float's signed coefficient by increasing its magnitude
    /// and decreasing its exponent accordingly. Greatly simplified a lot of
    /// private logic that involves comparing signed coefficients as integers,
    /// or wanting them to have comparable magnitudes.
    ///
    /// The coefficient is always fully maximized. Near `type(int256).min` the
    /// exponent cannot take the whole shift, so it stops at the floor and the
    /// digits it could not take are returned as the shortfall. The input value
    /// is then `signedCoefficient * 10^(exponent - shortfall)`.
    /// @return signedCoefficient The maximized signed coefficient.
    /// @return exponent The maximized exponent.
    /// @return shortfall The digits of shift the exponent could not take, in
    /// [0, 76]. Nonzero only when the exponent is `type(int256).min`.
    function maximize(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256, int256) {
        unchecked {
            if (signedCoefficient == 0) {
                return (MAXIMIZED_ZERO_SIGNED_COEFFICIENT, MAXIMIZED_ZERO_EXPONENT, 0);
            }

            int256 maximizedExponent = exponent;
            assembly ("memory-safe") {
                // Check if already maximized before dropping into a block full
                // of jumps.
                if iszero(sdiv(signedCoefficient, E75)) {
                    if iszero(sdiv(signedCoefficient, E38)) {
                        signedCoefficient := mul(signedCoefficient, E38)
                        maximizedExponent := sub(maximizedExponent, 38)
                    }
                    if iszero(sdiv(signedCoefficient, E57)) {
                        signedCoefficient := mul(signedCoefficient, E19)
                        maximizedExponent := sub(maximizedExponent, 19)
                    }
                    if iszero(sdiv(signedCoefficient, E66)) {
                        signedCoefficient := mul(signedCoefficient, E10)
                        maximizedExponent := sub(maximizedExponent, 10)
                    }
                    for {} iszero(sdiv(signedCoefficient, E74)) {} {
                        signedCoefficient := mul(signedCoefficient, 100)
                        maximizedExponent := sub(maximizedExponent, 2)
                    }
                    if iszero(sdiv(signedCoefficient, E75)) {
                        signedCoefficient := mul(signedCoefficient, 10)
                        maximizedExponent := sub(maximizedExponent, 1)
                    }
                }
                // Maybe we can fit in one more OOM without overflow, but we
                // won't know until we try. This pushes us into
                // [1e76,type(int256).max] and [-type(int256).max,-1e76] ranges,
                // if that's possible.
                if lt(add(signedCoefficient, TIMES_TEN_MAX), TIMES_TEN_SPAN) {
                    signedCoefficient := mul(signedCoefficient, 10)
                    maximizedExponent := sub(maximizedExponent, 1)
                }
            }

            // The shift is at most 76, so the exponent wrapped past the floor
            // exactly when it went up.
            if (maximizedExponent > exponent) {
                return (signedCoefficient, type(int256).min, type(int256).max - maximizedExponent + 1);
            }
            return (signedCoefficient, maximizedExponent, 0);
        }
    }
}
