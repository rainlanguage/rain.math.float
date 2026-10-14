// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibDecimalFloat, Float} from "../../src/lib/LibDecimalFloat.sol";
import {UnformatableExponent} from "../../src/error/ErrFormat.sol";

/// `LibFormatDecimalFloat`'s digit-buffer algorithm with every assembly block
/// written as plain Solidity: digits go backwards into a buffer, then are
/// copied into an output of exact length, and trailing zeros come out with the
/// same 64/32/16/8/4/2/1 cascade. Gas comparison only, isolating the assembly.
/// GAS AND EQUIVALENCE BASELINE ONLY, NEVER A VALUE ORACLE: the same algorithm
/// in plain Solidity, to measure the assembly against. Expected strings come
/// from `expectedFormat` in `LibFormatDecimalFloat.toDecimalString.t.sol`.
library LibFormatDecimalFloatSolidity {
    int256 internal constant MAX_NON_SCIENTIFIC_EXPONENT = 1000;

    /// Longer than any uint256 in decimal.
    uint256 private constant DIGITS_BUFFER = 78;
    /// Longer than any display exponent magnitude, int32 plus 76, in decimal.
    uint256 private constant EXPONENT_BUFFER = 11;

    /// `LibFormatDecimalFloat.toDecimalString` with its assembly written as
    /// plain Solidity; see its NatSpec there.
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

    /// The decimal digits of `value`, written backwards into the end of a
    /// `DIGITS_BUFFER` byte buffer, and the index of the first.
    function _digits(uint256 value) private pure returns (bytes memory buffer, uint256 start) {
        buffer = new bytes(DIGITS_BUFFER);
        start = DIGITS_BUFFER;
        unchecked {
            do {
                start--;
                // A decimal digit fits uint8.
                // forge-lint: disable-next-line(unsafe-typecast)
                buffer[start] = bytes1(uint8(48 + value % 10));
                value /= 10;
            } while (value != 0);
        }
    }

    /// `LibFormatDecimalFloat._toScientific` with its assembly written as plain
    /// Solidity; see its NatSpec there.
    function _toScientific(int256 signedCoefficient, int256 exponent) private pure returns (string memory) {
        bool isNeg = signedCoefficient < 0;
        uint256 absCoef;
        unchecked {
            // forge-lint: disable-next-line(unsafe-typecast)
            absCoef = isNeg ? uint256(-signedCoefficient) : uint256(signedCoefficient);
        }
        (uint256 significand, uint256 trailingZeros) = stripTrailingZeros(absCoef);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 displayExponent = exponent + int256(trailingZeros);

        unchecked {
            (bytes memory digitBuffer, uint256 start) = _digits(significand);
            uint256 digits = DIGITS_BUFFER - start;
            // forge-lint: disable-next-line(unsafe-typecast)
            displayExponent += int256(digits) - 1;

            bool expNeg = displayExponent < 0;
            bytes memory expBuffer = new bytes(EXPONENT_BUFFER);
            uint256 eStart = EXPONENT_BUFFER;
            if (displayExponent != 0) {
                // displayExponent is within int32 plus 76, so its negation fits.
                // forge-lint: disable-next-line(unsafe-typecast)
                uint256 e = expNeg ? uint256(-displayExponent) : uint256(displayExponent);
                do {
                    eStart--;
                    // A decimal digit fits uint8.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    expBuffer[eStart] = bytes1(uint8(48 + e % 10));
                    e /= 10;
                } while (e != 0);
            }

            uint256 length = (isNeg ? 1 : 0) + (digits > 1 ? digits + 1 : 1);
            if (displayExponent != 0) {
                length += 1 + (expNeg ? 1 : 0) + (EXPONENT_BUFFER - eStart);
            }
            bytes memory out = new bytes(length);
            uint256 cursor = 0;
            if (isNeg) {
                out[cursor++] = "-";
            }
            out[cursor++] = digitBuffer[start];
            if (digits > 1) {
                out[cursor++] = ".";
                for (uint256 i = start + 1; i < DIGITS_BUFFER; i++) {
                    out[cursor++] = digitBuffer[i];
                }
            }
            if (displayExponent != 0) {
                out[cursor++] = "e";
                if (expNeg) {
                    out[cursor++] = "-";
                }
                for (uint256 i = eStart; i < EXPONENT_BUFFER; i++) {
                    out[cursor++] = expBuffer[i];
                }
            }
            return string(out);
        }
    }

    /// `LibFormatDecimalFloat._toNonScientific` with its assembly written as
    /// plain Solidity; see its NatSpec there.
    function _toNonScientific(int256 signedCoefficient, int256 exponent) private pure returns (string memory) {
        bool isNeg = signedCoefficient < 0;
        uint256 absCoef;
        unchecked {
            // forge-lint: disable-next-line(unsafe-typecast)
            absCoef = isNeg ? uint256(-signedCoefficient) : uint256(signedCoefficient);
        }

        (uint256 significand, uint256 trailingZeros) = stripTrailingZeros(absCoef);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 effExp = exponent + int256(trailingZeros);
        if (effExp > MAX_NON_SCIENTIFIC_EXPONENT || effExp < -MAX_NON_SCIENTIFIC_EXPONENT) {
            revert UnformatableExponent(effExp);
        }

        unchecked {
            (bytes memory digitBuffer, uint256 start) = _digits(significand);
            uint256 digits = DIGITS_BUFFER - start;
            uint256 sign = isNeg ? 1 : 0;
            bytes memory out;
            uint256 cursor = sign;
            if (effExp >= 0) {
                // effExp <= 1000.
                // forge-lint: disable-next-line(unsafe-typecast)
                uint256 zeros = uint256(effExp);
                out = new bytes(sign + digits + zeros);
                for (uint256 i = start; i < DIGITS_BUFFER; i++) {
                    out[cursor++] = digitBuffer[i];
                }
                for (uint256 i = 0; i < zeros; i++) {
                    out[cursor++] = "0";
                }
            } else {
                // -effExp <= 1000.
                // forge-lint: disable-next-line(unsafe-typecast)
                uint256 fractionDigits = uint256(-effExp);
                if (digits <= fractionDigits) {
                    out = new bytes(sign + 2 + fractionDigits);
                    out[cursor++] = "0";
                    out[cursor++] = ".";
                    uint256 leadingZeros = fractionDigits - digits;
                    for (uint256 i = 0; i < leadingZeros; i++) {
                        out[cursor++] = "0";
                    }
                    for (uint256 i = start; i < DIGITS_BUFFER; i++) {
                        out[cursor++] = digitBuffer[i];
                    }
                } else {
                    out = new bytes(sign + digits + 1);
                    uint256 point = start + digits - fractionDigits;
                    for (uint256 i = start; i < point; i++) {
                        out[cursor++] = digitBuffer[i];
                    }
                    out[cursor++] = ".";
                    for (uint256 i = point; i < DIGITS_BUFFER; i++) {
                        out[cursor++] = digitBuffer[i];
                    }
                }
            }
            if (isNeg) {
                out[0] = "-";
            }
            return string(out);
        }
    }

    /// `LibFormatDecimalFloat.stripTrailingZeros` with its assembly written as
    /// plain Solidity; see its NatSpec there.
    function stripTrailingZeros(uint256 value) private pure returns (uint256 significand, uint256 trailingZeros) {
        unchecked {
            if (value % 10 == 0) {
                if (value % 1e64 == 0) {
                    value /= 1e64;
                    trailingZeros = 64;
                }
                if (value % 1e32 == 0) {
                    value /= 1e32;
                    trailingZeros += 32;
                }
                if (value % 1e16 == 0) {
                    value /= 1e16;
                    trailingZeros += 16;
                }
                if (value % 1e8 == 0) {
                    value /= 1e8;
                    trailingZeros += 8;
                }
                if (value % 1e4 == 0) {
                    value /= 1e4;
                    trailingZeros += 4;
                }
                if (value % 100 == 0) {
                    value /= 100;
                    trailingZeros += 2;
                }
                if (value % 10 == 0) {
                    value /= 10;
                    trailingZeros += 1;
                }
            }
            significand = value;
        }
    }
}
