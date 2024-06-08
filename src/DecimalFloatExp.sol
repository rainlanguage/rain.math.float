// SPDX-License-Identifier: CAL
pragma solidity ^0.8.25;

import {SIGN_MASK, LibDecimalFloat, DivisionByZero, COMPARE_EQUAL, COMPARE_LESS_THAN} from "./DecimalFloat.sol";

/// Experimental versions of algorithms for DecimalFloat.
library LibDecimalFloatExp {
    // /// Long division logic for DecimalFloat.
    // function divideLong(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB) internal pure returns (int256, int256) {
    //     if (signedCoefficientA == 0) {
    //         return (0, 0);
    //     }

    //     if (signedCoefficientB == 0) {
    //         revert DivisionByZero();
    //     }

    //     uint256 unsignedCoefficientA = uint256(uint128(signedCoefficientA) & ~SIGN_MASK);
    //     uint256 unsignedCoefficientB = uint256(uint128(signedCoefficientB) & ~SIGN_MASK);

    //     int128 adjust = 0;
    //     int256 resultCoefficient = 0;

    //     unchecked {
    //         while (unsignedCoefficientA < unsignedCoefficientB) {
    //             unsignedCoefficientA *= 10;
    //             adjust += 1;
    //         }

    //         uint256 tensB = unsignedCoefficientB * 10;
    //         while (unsignedCoefficientA >= tensB) {
    //             unsignedCoefficientB = tensB;
    //             tensB *= 10;
    //             adjust -= 1;
    //         }

    //         uint256 tmpCoefficientA = unsignedCoefficientA;

    //         while (true) {
    //             while (tmpCoefficientA >= unsignedCoefficientB) {
    //                 tmpCoefficientA -= unsignedCoefficientB;
    //                 resultCoefficient += 1;
    //             }

    //             // Discard this round as it caused precision loss in the result.
    //             if (int128(resultCoefficient) != int256(resultCoefficient)) {
    //                 break;
    //             }

    //             unsignedCoefficientA = tmpCoefficientA;

    //             if (tmpCoefficientA == 0 && adjust >= 0) {
    //                 break;
    //             }

    //             tmpCoefficientA *= 10;
    //             resultCoefficient *= 10;
    //             adjust += 1;
    //         }
    //     }

    //     int256 exponent = exponentA - exponentB - adjust;

    //     (int256 normalizedCoefficient, int256 normalizedExponent) =
    //         LibDecimalFloat.normalize(resultCoefficient, exponent);

    //     uint256 signBit = signedCoefficientA & SIGN_MASK ^ signedCoefficientB & SIGN_MASK;

    //     return (normalizedCoefficient & ~SIGN_MASK | signBit, normalizedExponent);
    // }

    /// https://www.ams.org/journals/mcom/1954-08-046/S0025-5718-1954-0061464-9/S0025-5718-1954-0061464-9.pdf
    function log10Iterative(int256 signedCoefficientB, int256 exponentB, uint256 precision)
        internal
        pure
        returns (int256, int256)
    {
        unchecked {
            // Maximizing B can make some comparisons faster.
            (signedCoefficientB, exponentB) = LibDecimalFloat.maximize(signedCoefficientB, exponentB);

            // We start with a0 in A, ax in B, 1 in C and F, and 0 in D and E. The
            // latest approximation to log a0 a1 is always E/F.
            // Maximised form of 10 is 1e38e-37
            int256 signedCoefficientA = 1e38;
            int256 exponentA = -37;

            // C and E get swapped to merge them. C is high 128 bits, E is low.
            // C initial is 1
            // E initial is 0
            uint256 ce = 1 << 0x80;

            // D and F get swapped to merge them. D is high 128 bits, F is low.
            // D initial is 0
            // F initial is 1
            uint256 df = 1;

            uint256 i = 0;
            while (i < precision) {
                // Operation II (if A < B) :
                if (LibDecimalFloat.compare(signedCoefficientA, exponentA, signedCoefficientB, exponentB) == COMPARE_LESS_THAN) {
                    // We interchange A and B, C and E, D and F.
                    int256 tmpDecimalPart = signedCoefficientB;
                    signedCoefficientB = signedCoefficientA;
                    signedCoefficientA = tmpDecimalPart;

                    tmpDecimalPart = exponentB;
                    exponentB = exponentA;
                    exponentA = tmpDecimalPart;

                    ce = ce << 0x80 | ce >> 0x80;
                    df = df << 0x80 | df >> 0x80;

                    i++;
                }
                // Operation I (if A >= B) :
                else {
                    // We put A/B in A, C + E in C, and D + F in D.
                    (signedCoefficientA, exponentA) =
                        LibDecimalFloat.divide(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

                    {
                        uint256 c = ce >> 0x80;
                        uint256 e = ce & type(uint128).max;
                        ce = ((c + e) << 0x80) | e;
                    }

                    {
                        uint256 d = df >> 0x80;
                        uint256 f = df & type(uint128).max;
                        df = ((d + f) << 0x80) | f;
                    }
                }

                // If it happens that the logarithm is a rational number, for
                // instance log8 4 = 2/3, then at some point B becomes 1, the exact
                // log is obtained and no further changes in E or F occurs.
                // Comparing a probably maximized B to a maximized one should be
                // most efficient to compare.
                if (LibDecimalFloat.compare(signedCoefficientB, exponentB, 1e38, -38) == COMPARE_EQUAL) {
                    break;
                }
            }

            uint256 eFinal = ce & type(uint128).max;
            uint256 fFinal = df & type(uint128).max;
            return LibDecimalFloat.divide(int256(eFinal), 0, int256(fFinal), 0);
        }
    }
}
