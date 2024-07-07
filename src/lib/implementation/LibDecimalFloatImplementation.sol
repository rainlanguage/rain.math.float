// SPDX-License-Identifier: CAL
pragma solidity ^0.8.25;

import {ExponentOverflow} from "../../error/ErrDecimalFloat.sol";

library LibDecimalFloatImplementation {
    /// https://speleotrove.com/decimal/daops.html#refaddsub
    /// > add and subtract both take two operands. If either operand is a special
    /// > value then the general rules apply.
    /// >
    /// > Otherwise, the operands are added (after inverting the sign used for
    /// > the second operand if the operation is a subtraction), as follows:
    /// >
    /// > The coefficient of the result is computed by adding or subtracting the
    /// > aligned coefficients of the two operands. The aligned coefficients are
    /// > computed by comparing the exponents of the operands:
    /// >
    /// > - If they have the same exponent, the aligned coefficients are the same
    /// > as the original coefficients.
    /// > - Otherwise the aligned coefficient of the number with the larger
    /// > exponent is its original coefficient multiplied by 10^n, where n is the
    /// > absolute difference between the exponents, and the aligned coefficient
    /// > of the other operand is the same as its original coefficient.
    /// >
    /// > If the signs of the operands differ then the smaller aligned
    /// > coefficient is subtracted from the larger; otherwise they are added.
    /// >
    /// > The exponent of the result is the minimum of the exponents of the two
    /// > operands.
    /// >
    /// > The sign of the result is determined as follows:
    /// >
    /// > - If the result is non-zero then the sign of the result is the sign of
    /// > the operand having the larger absolute value.
    /// > - Otherwise, the sign of a zero result is 0 unless either both operands
    /// > were negative or the signs of the operands were different and the
    /// > rounding is round-floor.
    function addRaw(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
        int256 smallerExponent;
        int256 adjustedCoefficient;

        {
            int256 largerExponent;
            int256 staticCoefficient;
            if (exponentA > exponentB) {
                smallerExponent = exponentB;
                largerExponent = exponentA;
                adjustedCoefficient = signedCoefficientA;
                staticCoefficient = signedCoefficientB;
            } else {
                smallerExponent = exponentA;
                largerExponent = exponentB;
                adjustedCoefficient = signedCoefficientB;
                staticCoefficient = signedCoefficientA;
            }

            if (adjustedCoefficient > 0) {
                uint256 alignmentExponentDiff;
                unchecked {
                    alignmentExponentDiff = uint256(largerExponent - smallerExponent);
                }
                uint256 multiplier = 10 ** alignmentExponentDiff;
                if (multiplier > uint256(type(int256).max)) {
                    revert ExponentOverflow();
                }
                adjustedCoefficient *= int256(multiplier);
            }

            // This can't overflow because the signed coefficient is 128 bits.
            // Worst case scenario is that one was aligned all the way to fill
            // the high 128 bits, which we add to the max low 128 bits, which
            // doesn't overflow.
            unchecked {
                adjustedCoefficient += staticCoefficient;
            }
        }

        return (adjustedCoefficient, smallerExponent);
    }
}
