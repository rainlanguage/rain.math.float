// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {ExponentOverflow, ExponentUnderflow, CoefficientOverflow} from "src/error/ErrDecimalFloat.sol";
import {
    LibDecimalFloatImplementation,
    MAXIMIZED_ZERO_SIGNED_COEFFICIENT,
    MAXIMIZED_ZERO_EXPONENT
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

/// `mul`, `maximize`, `packLossy`, `packLossless` and `packArithmeticResult`
/// verbatim from main 2e1f8840fabaf3f189654bc1bba13d748a15c30b, before the
/// gas changes of issue #310. The helpers they call are unchanged since that
/// commit, so they are qualified to the live library. Equivalence tests only.
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
                LibDecimalFloatImplementation.mulDiv(
                    signedCoefficientAAbs, signedCoefficientBAbs, uint256(10) ** adjustExponent
                ),
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

    function packLossy(int256 signedCoefficient, int256 exponent) internal pure returns (Float float, bool lossless) {
        unchecked {
            int256 initialSignedCoefficient = signedCoefficient;
            int256 initialExponent = exponent;

            // truncation here is intentional if it happens as that is what we
            // are testing for.
            // forge-lint: disable-next-line(unsafe-typecast)
            bool fits = int224(signedCoefficient) == signedCoefficient;

            if (!fits) {
                if (signedCoefficient / 1e72 != 0) {
                    signedCoefficient /= 1e5;
                    exponent += 5;
                }

                // truncation here is intentional if it happens as that is what we
                // are testing for.
                // forge-lint: disable-next-line(unsafe-typecast)
                while (int224(signedCoefficient) != signedCoefficient) {
                    signedCoefficient /= 10;
                    ++exponent;
                }
            } else {
                if (signedCoefficient == 0) {
                    // The literal is the bool this function returns, not a condition operand.
                    //forge-lint: disable-next-line(boolean-cst)
                    return (LibDecimalFloat.FLOAT_ZERO, true);
                }
            }

            // truncation here is intentional if it happens as that is what we
            // are testing for.
            // forge-lint: disable-next-line(unsafe-typecast)
            if (int32(exponent) != exponent) {
                // Shedding raises the exponent by at most ten digits, so an
                // exponent past the ceiling started positive, and one that
                // started positive and is out of range is past the ceiling,
                // or wrapped through int256.max by the unchecked shedding.
                if (initialExponent > 0) {
                    // Lower the exponent by multiplying the coefficient by ten
                    // per step, which is exact, while int224 has the headroom.
                    // A coefficient shed to fit int224 has none, and a non-zero
                    // int224 has at most 68 digits so an excess of 68 or more
                    // never has it. Either way the magnitude exceeds every
                    // representable Float.
                    int256 excess = exponent - type(int32).max;
                    if (!fits || excess > 67) {
                        revert ExponentOverflow(initialSignedCoefficient, initialExponent);
                    }
                    // excess is in [1, 67] so 10 ** excess fits int256 and the
                    // casts cannot truncate.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    int256 scale = int256(10 ** uint256(excess));
                    // Nothing was shed, so the initial coefficient is the one to
                    // lift.
                    if (
                        initialSignedCoefficient > type(int224).max / scale
                            || initialSignedCoefficient < type(int224).min / scale
                    ) {
                        revert ExponentOverflow(initialSignedCoefficient, initialExponent);
                    }
                    signedCoefficient = initialSignedCoefficient * scale;
                    exponent = type(int32).max;
                } else {
                    // The exponent is below the int32 floor. Every division of the
                    // coefficient by ten raises the exponent by one, so the
                    // shortfall is exactly the number of digits to shed. The
                    // coefficient fits int224 here, so it has at most 68 decimal
                    // digits and a shortfall of 68 or more sheds every one of
                    // them: that is zero without computing it. `exponent` is
                    // negative here and below int32.min, so the subtraction cannot
                    // overflow and the shortfall is positive.
                    int256 shortfall = int256(type(int32).min) - exponent;
                    if (shortfall > 67) {
                        // The literal is the bool this function returns, not a condition operand.
                        //forge-lint: disable-next-line(boolean-cst)
                        return (LibDecimalFloat.FLOAT_ZERO, false);
                    }
                    // shortfall is in [1, 67] so 10 ** shortfall fits int256 and the
                    // casts cannot truncate.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    signedCoefficient /= int256(10 ** uint256(shortfall));
                    if (signedCoefficient == 0) {
                        // Every digit was shed: the value is smaller in magnitude
                        // than any representable Float, so this is the underflow
                        // zero and it is not a lossless conversion.
                        // The literal is the bool this function returns, not a condition operand.
                        //forge-lint: disable-next-line(boolean-cst)
                        return (LibDecimalFloat.FLOAT_ZERO, false);
                    }
                    exponent = type(int32).min;
                }
            }

            // Lossless iff every digit shed was a zero, which is iff the
            // original coefficient is an exact multiple of ten to the number of
            // digits shed. Shedding only raises the exponent and lifting only
            // lowers it, and never both, so an exponent at or below the initial
            // one shed nothing. Otherwise the number shed is the rise, which is
            // in [1, 76] for any non-zero result (an int256 has at most 77
            // digits and at least one survived), so the power fits int256.
            if (exponent <= initialExponent) {
                // The literal is the bool this function returns, not a condition operand.
                //forge-lint: disable-next-line(boolean-cst)
                lossless = true;
            } else {
                // The rise is in [1, 76] so the casts cannot truncate.
                // forge-lint: disable-next-line(unsafe-typecast)
                lossless = initialSignedCoefficient % int256(10 ** uint256(exponent - initialExponent)) == 0;
            }

            // Need a mask to zero out the bits that could be set to 1 if the
            // coefficient is negative.
            uint256 mask = type(uint224).max;
            assembly ("memory-safe") {
                float := or(and(signedCoefficient, mask), shl(0xe0, exponent))
            }
        }
    }

    function packLossless(int256 signedCoefficient, int256 exponent) internal pure returns (Float) {
        (Float c, bool lossless) = packLossy(signedCoefficient, exponent);
        if (!lossless) {
            revert CoefficientOverflow(signedCoefficient, exponent);
        }
        return c;
    }

    function packArithmeticResult(int256 signedCoefficient, int256 exponent) internal pure returns (Float) {
        (Float c, bool lossless) = packLossy(signedCoefficient, exponent);
        if (!lossless && Float.unwrap(c) == bytes32(0)) {
            revert ExponentUnderflow(signedCoefficient, exponent);
        }
        return c;
    }
}
