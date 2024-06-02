// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

error SignOverflow(uint256 badSign);
error ExponentOverflow(int256 badExponent);
error CoefficientOverflow(uint256 badCoefficient);

type DecimalFloat is uint256;

uint256 constant COEFFICIENT_BITS = 256 - 17;
uint256 constant COEFFICIENT_MASK = (1 << COEFFICIENT_BITS) - 1;

uint256 constant EXPONENT_BITS = 16;
uint256 constant EXPONENT_MASK = type(uint16).max;

library LibDecimalFloat {
    function fromParts(uint256 sign, uint256 coefficient, int256 exponent) internal pure returns (DecimalFloat) {
        if (sign > 1) {
            revert SignOverflow(sign);
        }
        if (exponent < type(int16).min || exponent > type(int16).max) {
            revert ExponentOverflow(exponent);
        }
        if (coefficient > COEFFICIENT_MASK) {
            revert CoefficientOverflow(coefficient);
        }

        DecimalFloat value;
        uint256 exponentMask = EXPONENT_MASK;
        uint256 coefficientBits = COEFFICIENT_BITS;
        assembly ("memory-safe") {
            // Exponent is signed so we have to zero out the top bits.
            exponent := and(exponent, exponentMask)
            value := or(coefficient, shl(coefficientBits, exponent))
            value := or(value, shl(0xFF, sign))
        }
        return value;
    }

    function toParts(DecimalFloat value) internal pure returns (uint256 sign, uint256 coefficient, int256 exponent) {
        uint256 coefficientMask = COEFFICIENT_MASK;
        assembly ("memory-safe") {
            sign := shr(0xFF, value)
            coefficient := and(value, coefficientMask)
            exponent := sar(0xF0, shl(1, value))
        }
    }
}
