// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {ExponentOverflow} from "src/error/ErrDecimalFloat.sol";
import {
    LibDecimalFloatImplementation,
    MAXIMIZED_ZERO_SIGNED_COEFFICIENT,
    MAXIMIZED_ZERO_EXPONENT
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

/// `mul` and its two cold helpers verbatim from
/// `src/lib/implementation/LibDecimalFloatImplementation.sol` at
/// 26cd9e86, before the packed-exponent fast path. The helpers it calls are
/// called on the live library. EQUIVALENCE BASELINE ONLY, NEVER A VALUE
/// ORACLE: it copies the old steps, so agreeing with it says nothing about a
/// value. Expected values come from `LibTestExactDecimal` over exact math.
library LibDecimalFloatImplementationMulPr307 {
    function mul(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256 signedCoefficient, int256 exponent)
    {
        bool isZero;
        assembly ("memory-safe") {
            isZero := or(iszero(signedCoefficientA), iszero(signedCoefficientB))
        }
        if (isZero) {
            // These sets are redundant as both are zero but this makes it
            // clearer and more explicit.
            signedCoefficient = MAXIMIZED_ZERO_SIGNED_COEFFICIENT;
            exponent = MAXIMIZED_ZERO_EXPONENT;
        } else {
            unchecked {
                exponent = exponentA + exponentB;
            }
            if (exponentB < 0) {
                if (exponent > exponentA) {
                    return mulExponentBelowFloor(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
                }
            } else if (exponent < exponentA) {
                return mulExponentNearCeiling(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
            }
            // The lift below adds at most 77 and `unabsUnsignedMulOrDivLossy`
            // at most 1.
            if (exponent > type(int256).max - 78) {
                return mulExponentNearCeiling(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
            }

            // mulDiv only works with unsigned integers, so get the absolute
            // values of the coefficients.
            uint256 signedCoefficientAAbs =
                LibDecimalFloatImplementation.absUnsignedSignedCoefficient(signedCoefficientA);
            uint256 signedCoefficientBAbs =
                LibDecimalFloatImplementation.absUnsignedSignedCoefficient(signedCoefficientB);

            (uint256 prod1,) = LibDecimalFloatImplementation.mul512(signedCoefficientAAbs, signedCoefficientBAbs);

            uint256 adjustExponent = 0;
            unchecked {
                if (prod1 > 1e37) {
                    prod1 /= 1e37;
                    adjustExponent += 37;
                }
                if (prod1 > 1e18) {
                    prod1 /= 1e18;
                    adjustExponent += 18;
                }
                if (prod1 > 1e9) {
                    prod1 /= 1e9;
                    adjustExponent += 9;
                }
                if (prod1 > 1e4) {
                    prod1 /= 1e4;
                    adjustExponent += 4;
                }
                while (prod1 > 0) {
                    prod1 /= 10;
                    adjustExponent++;
                }

                // adjustExponent [0, 77]
                // forge-lint: disable-next-line(unsafe-typecast)
                exponent += int256(adjustExponent);
            }

            (signedCoefficient, exponent) = LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(
                signedCoefficientA,
                signedCoefficientB,
                LibDecimalFloatImplementation.mulDiv(
                    signedCoefficientAAbs, signedCoefficientBAbs, uint256(10) ** adjustExponent
                ),
                exponent
            );
        }
    }

    /// `mul` for operands whose exponent sum is below `type(int256).min`. The
    /// product is taken with each exponent 2^254 higher, then moved back down,
    /// shedding the digits that do not fit above the floor.
    function mulExponentBelowFloor(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) private pure returns (int256 signedCoefficient, int256 exponent) {
        unchecked {
            int256 shift = 2 ** 254;
            (signedCoefficient, exponent) =
                mul(signedCoefficientA, exponentA + shift, signedCoefficientB, exponentB + shift);
            if (exponent >= 0) {
                return (signedCoefficient, exponent + type(int256).min);
            }
            if (exponent < -76) {
                return (MAXIMIZED_ZERO_SIGNED_COEFFICIENT, MAXIMIZED_ZERO_EXPONENT);
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            signedCoefficient /= int256(10 ** uint256(-exponent));
            exponent = signedCoefficient == 0 ? MAXIMIZED_ZERO_EXPONENT : type(int256).min;
        }
    }

    /// `mul` for operands whose exponent sum is above `type(int256).max - 78`,
    /// where the normalisation can lift the exponent past `type(int256).max`.
    /// Reverts `ExponentOverflow` when the result exponent does not fit.
    function mulExponentNearCeiling(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) private pure returns (int256 signedCoefficient, int256 exponent) {
        (signedCoefficient, exponent) = mul(signedCoefficientA, 0, signedCoefficientB, 0);
        unchecked {
            int256 sum = exponentA + exponentB;
            int256 result = sum + exponent;
            if ((exponentB >= 0 && sum < exponentA) || result < sum) {
                revert ExponentOverflow(signedCoefficientA, exponentA);
            }
            exponent = result;
        }
    }
}
