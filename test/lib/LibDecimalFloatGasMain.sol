// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {ExponentOverflow} from "src/error/ErrDecimalFloat.sol";
import {
    LibDecimalFloatImplementation,
    MAXIMIZED_ZERO_SIGNED_COEFFICIENT,
    MAXIMIZED_ZERO_EXPONENT
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

/// `mul`, `mulExponentBelowFloor`, `mulExponentNearCeiling` and `maximize`
/// verbatim from main 8fd3980250fae214fc2b4273545654ee1921c0ad, before the
/// gas changes of issue #310. The helpers they call are unchanged on main, so
/// they are qualified to the live library. Equivalence tests only.
library LibDecimalFloatGasMain {
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
            // Both exponents in [-2^253, 2^253) cannot wrap the sum or reach
            // the ceiling margin below, so packed operands pay one branch.
            bool isWide;
            assembly ("memory-safe") {
                isWide := shr(254, or(add(exponentA, shl(253, 1)), add(exponentB, shl(253, 1))))
            }
            if (isWide) {
                if (exponentB < 0) {
                    if (exponent > exponentA) {
                        return mulExponentBelowFloor(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
                    }
                } else if (exponent < exponentA) {
                    return mulExponentNearCeiling(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
                }
                // The lift below adds at most 77 and
                // `unabsUnsignedMulOrDivLossy` at most 1.
                if (exponent > type(int256).max - 78) {
                    return mulExponentNearCeiling(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
                }
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
                LibDecimalFloatImplementation.mulDivPow10(signedCoefficientAAbs, signedCoefficientBAbs, adjustExponent),
                exponent
            );
        }
    }

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

    function maximize(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256, int256) {
        unchecked {
            if (signedCoefficient == 0) {
                return (MAXIMIZED_ZERO_SIGNED_COEFFICIENT, MAXIMIZED_ZERO_EXPONENT, 0);
            }

            int256 maximizedExponent = exponent;
            // Check if already maximized before dropping into a block full of
            // jumps.
            if (signedCoefficient / 1e75 == 0) {
                if (signedCoefficient / 1e38 == 0) {
                    signedCoefficient *= 1e38;
                    maximizedExponent -= 38;
                }

                if (signedCoefficient / 1e57 == 0) {
                    signedCoefficient *= 1e19;
                    maximizedExponent -= 19;
                }

                if (signedCoefficient / 1e66 == 0) {
                    signedCoefficient *= 1e10;
                    maximizedExponent -= 10;
                }

                while (signedCoefficient / 1e74 == 0) {
                    signedCoefficient *= 1e2;
                    maximizedExponent -= 2;
                }

                if (signedCoefficient / 1e75 == 0) {
                    signedCoefficient *= 10;
                    maximizedExponent -= 1;
                }
            }

            // Maybe we can fit in one more OOM without overflow, but we won't
            // know until we try. This pushes us into [1e76,type(int256).max] and
            // [-type(int256).max,-1e76] ranges, if that's possible.
            int256 trySignedCoefficient = signedCoefficient * 10;
            if (signedCoefficient == trySignedCoefficient / 10) {
                signedCoefficient = trySignedCoefficient;
                maximizedExponent -= 1;
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
