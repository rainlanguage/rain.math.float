// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    ExponentOverflow,
    Log10Negative,
    Log10Zero,
    DivisionByZero,
    MaximizeOverflow
} from "src/error/ErrDecimalFloat.sol";
import {LOG_MANTISSA_LAST_INDEX} from "src/lib/table/LibLogTable.sol";
import {
    LibDecimalFloatImplementation,
    ADD_MAX_EXPONENT_DIFF,
    MAXIMIZED_ZERO_SIGNED_COEFFICIENT,
    MAXIMIZED_ZERO_EXPONENT,
    LOG10_Y_EXPONENT
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

/// `maximize`, `maximizeFull`, `div`, `add`, `sub`, `inv` and `log10` verbatim
/// from `src/lib/implementation/LibDecimalFloatImplementation.sol` at main
/// 2b19ed13b90420ffc74dcb528f9f67e9e71b315e, before `maximize` returned a
/// shortfall. Every helper they call is unchanged since that commit, so it is
/// called on the live library. Equivalence tests only.
library LibDecimalFloatImplementationMain {
    function maximize(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256, bool) {
        unchecked {
            if (signedCoefficient == 0) {
                // The literal is the bool this function returns, not a condition operand.
                //forge-lint: disable-next-line(boolean-cst)
                return (MAXIMIZED_ZERO_SIGNED_COEFFICIENT, MAXIMIZED_ZERO_EXPONENT, true);
            }

            // Check if already maximized before dropping into a block full of
            // jumps.
            if (signedCoefficient / 1e75 == 0) {
                if (signedCoefficient / 1e38 == 0 && exponent >= type(int256).min + 38) {
                    signedCoefficient *= 1e38;
                    exponent -= 38;
                }

                if (signedCoefficient / 1e57 == 0 && exponent >= type(int256).min + 19) {
                    signedCoefficient *= 1e19;
                    exponent -= 19;
                }

                if (signedCoefficient / 1e66 == 0 && exponent >= type(int256).min + 10) {
                    signedCoefficient *= 1e10;
                    exponent -= 10;
                }

                while (signedCoefficient / 1e74 == 0 && exponent >= type(int256).min + 2) {
                    signedCoefficient *= 1e2;
                    exponent -= 2;
                }

                if (signedCoefficient / 1e75 == 0 && exponent >= type(int256).min + 1) {
                    signedCoefficient *= 10;
                    exponent -= 1;
                }
            }

            // Maybe we can fit in one more OOM without overflow, but we won't
            // know until we try. This pushes us into [1e76,type(int256).max] and
            // [-type(int256).max,-1e76] ranges, if that's possible.
            int256 trySignedCoefficient = signedCoefficient * 10;
            if (signedCoefficient == trySignedCoefficient / 10 && exponent >= type(int256).min + 1) {
                signedCoefficient = trySignedCoefficient;
                exponent -= 1;
            }

            return (signedCoefficient, exponent, signedCoefficient / 1e75 != 0);
        }
    }

    function maximizeFull(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        (int256 trySignedCoefficient, int256 tryExponent, bool full) = maximize(signedCoefficient, exponent);
        if (!full) {
            revert MaximizeOverflow(signedCoefficient, exponent);
        }
        return (trySignedCoefficient, tryExponent);
    }

    //slither-disable-next-line cyclomatic-complexity
    function div(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
        if (signedCoefficientB == 0) {
            revert DivisionByZero(signedCoefficientA, exponentA);
        } else if (signedCoefficientA == 0) {
            return (MAXIMIZED_ZERO_SIGNED_COEFFICIENT, MAXIMIZED_ZERO_EXPONENT);
        } else {
            int256 signedCoefficient;
            int256 exponent = 0;
            bool fullA;
            bool fullB;
            // Move both coefficients into the e75/e76 range, so that the result
            // of division will not cause a mulDiv overflow.
            (signedCoefficientA, exponentA, fullA) = maximize(signedCoefficientA, exponentA);
            (signedCoefficientB, exponentB, fullB) = maximize(signedCoefficientB, exponentB);
            // exponentA is pinned at its minimum, so the digits it cannot take
            // join adjustExponent, which spills onto exponentB. `exponent` holds
            // that shift until the quotient exponent is computed.
            if (!fullA) {
                (signedCoefficientA, exponent) = maximizeFull(signedCoefficientA, 0);
            }

            // mulDiv only works with unsigned integers, so get the absolute
            // values of the coefficients.
            uint256 signedCoefficientAAbs =
                LibDecimalFloatImplementation.absUnsignedSignedCoefficient(signedCoefficientA);
            uint256 signedCoefficientBAbs =
                LibDecimalFloatImplementation.absUnsignedSignedCoefficient(signedCoefficientB);

            uint256 scale = 1e76;
            int256 adjustExponent = 76;

            // We are going to scale the numerator up by the largest power of ten
            // that is smaller than the denominator. This will always overflow
            // internally to the mulDiv during the initial multiplication, in
            // 512 bits, but will subsequently always be reduced back down to
            // fit in 256 bits by the division of a denominator that is larger
            // than the scale up.
            if (signedCoefficientBAbs < scale) {
                if (fullB) {
                    scale = 1e75;
                    adjustExponent = 75;
                } else {
                    if (signedCoefficientBAbs < 1e38) {
                        if (signedCoefficientBAbs < 1e19) {
                            if (signedCoefficientBAbs < 1e10) {
                                if (signedCoefficientBAbs < 1e5) {
                                    scale = 1e5;
                                    adjustExponent = 5;
                                } else {
                                    scale = 1e10;
                                    adjustExponent = 10;
                                }
                            } else {
                                if (signedCoefficientBAbs < 1e14) {
                                    scale = 1e14;
                                    adjustExponent = 14;
                                } else {
                                    scale = 1e19;
                                    adjustExponent = 19;
                                }
                            }
                        } else {
                            if (signedCoefficientBAbs < 1e28) {
                                if (signedCoefficientBAbs < 1e23) {
                                    scale = 1e23;
                                    adjustExponent = 23;
                                } else {
                                    scale = 1e28;
                                    adjustExponent = 28;
                                }
                            } else {
                                if (signedCoefficientBAbs < 1e33) {
                                    scale = 1e33;
                                    adjustExponent = 33;
                                } else {
                                    scale = 1e38;
                                    adjustExponent = 38;
                                }
                            }
                        }
                    } else {
                        if (signedCoefficientBAbs < 1e58) {
                            if (signedCoefficientBAbs < 1e48) {
                                if (signedCoefficientBAbs < 1e43) {
                                    scale = 1e43;
                                    adjustExponent = 43;
                                } else {
                                    scale = 1e48;
                                    adjustExponent = 48;
                                }
                            } else {
                                if (signedCoefficientBAbs < 1e53) {
                                    scale = 1e53;
                                    adjustExponent = 53;
                                } else {
                                    scale = 1e58;
                                    adjustExponent = 58;
                                }
                            }
                        } else {
                            if (signedCoefficientBAbs < 1e68) {
                                if (signedCoefficientBAbs < 1e63) {
                                    scale = 1e63;
                                    adjustExponent = 63;
                                } else {
                                    scale = 1e68;
                                    adjustExponent = 68;
                                }
                            } else {
                                if (signedCoefficientBAbs < 1e73) {
                                    scale = 1e73;
                                    adjustExponent = 73;
                                } else {
                                    // Noop as we already have a starting scale.
                                }
                            }
                        }
                    }

                    // Finalize the scale after the binary search.
                    while (signedCoefficientBAbs <= scale) {
                        unchecked {
                            scale /= 10;
                            adjustExponent -= 1;
                        }
                    }
                    if (scale == 0) {
                        revert MaximizeOverflow(signedCoefficientB, exponentB);
                    }
                }
            }
            adjustExponent -= exponent;

            // Attempt to apply the exponent adjustment.
            // First we try to apply it to exponentA.
            // If we cannot fully apply it we try to apply the rest to exponentB.
            // If we still have some left over then we just return zero as
            // the difference in exponents is too large to represent in
            // a single result negative exponent.
            unchecked {
                if (exponentA >= type(int256).min + adjustExponent) {
                    exponentA -= adjustExponent;
                } else {
                    adjustExponent -= exponentA - type(int256).min;
                    exponentA = type(int256).min;

                    if (adjustExponent > 0) {
                        if (exponentB <= type(int256).max - adjustExponent) {
                            exponentB += adjustExponent;
                        } else {
                            return (MAXIMIZED_ZERO_SIGNED_COEFFICIENT, MAXIMIZED_ZERO_EXPONENT);
                        }
                    }
                }
            }

            int256 underflowExponentBy = 0;

            unchecked {
                // This is the only case that can underflow.
                if (exponentA < 0 && exponentB > 0) {
                    int256 headroom = exponentA - type(int256).min;
                    underflowExponentBy = exponentB > headroom ? exponentB - headroom : int256(0);
                }

                exponent = exponentA + underflowExponentBy - exponentB;

                (signedCoefficient, exponent) = LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(
                    signedCoefficientA,
                    signedCoefficientB,
                    LibDecimalFloatImplementation.mulDiv(signedCoefficientAAbs, scale, signedCoefficientBAbs),
                    exponent
                );

                if (underflowExponentBy > 0) {
                    if (underflowExponentBy > 76) {
                        // This means the exponent is too small to represent even if
                        // we truncate and downscale the signed coefficient.
                        return (MAXIMIZED_ZERO_SIGNED_COEFFICIENT, MAXIMIZED_ZERO_EXPONENT);
                    }

                    // underflowExponentBy [1, 76]
                    // forge-lint: disable-next-line(unsafe-typecast)
                    signedCoefficient /= int256(10 ** uint256(underflowExponentBy));
                    if (signedCoefficient == 0) {
                        exponent = MAXIMIZED_ZERO_EXPONENT;
                    }
                }
                return (signedCoefficient, exponent);
            }
        }
    }

    function add(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
        // Zero for either is the edge case but we have to guard against it.
        // Doing it eagerly with assembly is less gas than lazily with jumps.
        bool eitherZero;
        assembly ("memory-safe") {
            eitherZero := or(iszero(signedCoefficientA), iszero(signedCoefficientB))
        }
        if (eitherZero) {
            if (signedCoefficientA == 0) {
                return (signedCoefficientB, exponentB);
            } else {
                return (signedCoefficientA, exponentA);
            }
        }

        // Maximizing A and B gives us similar coefficients, which simplifies
        // detecting when their exponents are too far apart to add without
        // simply ignoring one of them.
        (signedCoefficientA, exponentA) = maximizeFull(signedCoefficientA, exponentA);
        (signedCoefficientB, exponentB) = maximizeFull(signedCoefficientB, exponentB);

        // We want A to represent the larger exponent. If this is not the case
        // then swap them.
        if (exponentB > exponentA) {
            int256 tmp = signedCoefficientA;
            signedCoefficientA = signedCoefficientB;
            signedCoefficientB = tmp;

            tmp = exponentA;
            exponentA = exponentB;
            exponentB = tmp;
        }

        // After maximization the signed coefficients are the same OOM in
        // magnitude. However, what we need is for the exponents to be the same.
        // If the exponents are close enough we can divide coefficient B by
        // some power of 10 to align their exponents without precision loss.
        // If the exponents are too far apart, then all the information in B
        // would be lost, so we can just ignore B and return A.
        unchecked {
            // exponentA >= exponentB so exponentA - exponentB will fit in
            // uint256.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 alignmentExponentDiff = uint256(exponentA - exponentB);
            // The early return here allows us to do unchecked pow on the
            // scaler and means we never revert due to overflow here.
            if (alignmentExponentDiff > ADD_MAX_EXPONENT_DIFF) {
                return (signedCoefficientA, exponentA);
            }
            // alignmentExponentDiff can't be greater than 76 so will pow
            // without truncation.
            // forge-lint: disable-next-line(unsafe-typecast)
            signedCoefficientB /= int256(10 ** alignmentExponentDiff);
        }

        // The actual addition step.
        unchecked {
            int256 c = signedCoefficientA + signedCoefficientB;
            bool didOverflow;
            assembly ("memory-safe") {
                let sameSignAB := iszero(shr(0xff, xor(signedCoefficientA, signedCoefficientB)))
                let sameSignAC := iszero(shr(0xff, xor(signedCoefficientA, c)))
                didOverflow := and(sameSignAB, iszero(sameSignAC))
            }
            // Be careful to handle overflow.
            if (didOverflow) {
                if (type(int256).max == exponentA) {
                    revert ExponentOverflow(signedCoefficientA, exponentA);
                }

                signedCoefficientA /= 10;
                signedCoefficientB /= 10;
                exponentA++;
                signedCoefficientA += signedCoefficientB;
            } else {
                signedCoefficientA = c;
            }
        }
        return (signedCoefficientA, exponentA);
    }

    function sub(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
        pure
        returns (int256, int256)
    {
        (signedCoefficientB, exponentB) = LibDecimalFloatImplementation.minus(signedCoefficientB, exponentB);
        return add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    function inv(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        return div(1e76, -76, signedCoefficient, exponent);
    }

    function log10(address tablesDataContract, int256 signedCoefficient, int256 exponent)
        internal
        view
        returns (int256, int256)
    {
        {
            int256 unmaximizedCoefficient = signedCoefficient;
            int256 unmaximizedExponent = exponent;
            (signedCoefficient, exponent) = maximizeFull(signedCoefficient, exponent);

            if (signedCoefficient <= 0) {
                if (signedCoefficient == 0) {
                    revert Log10Zero();
                } else {
                    revert Log10Negative(unmaximizedCoefficient, unmaximizedExponent);
                }
            }
        }

        // all powers of 10 look like 1 with a different exponent
        if (signedCoefficient == 1e76) {
            return (exponent + 76, 0);
        }
        bool isAtLeastE76 = signedCoefficient >= 1e76;

        // This is a positive log. i.e. log(x) where x >= 1.
        if (exponent >= (isAtLeastE76 ? -76 : -75)) {
            int256 y1Coefficient;
            int256 y2Coefficient;
            int256 x1Coefficient;
            int256 x2Coefficient;
            // exact powers of 10 are already caught above.
            // but e.g. 20 would be 2e76, -75 and true for isAtLeastE76
            // => adding exp 76 yields 1, which is the correct result.
            // 200 would be 2e76, -74 and true for isAtLeastE76
            // => adding exp 76 yields 2, which is the correct result.
            // however 90 would be 9e75, -74 and false for isAtLeastE76
            // => adding exp 75 yields 1, which is the correct result.
            // 900 would be 9e75, -73 and false for isAtLeastE76
            // => adding exp 75 yields 2, which is the correct result.
            int256 powerOfTen = exponent + int256(isAtLeastE76 ? int256(76) : int256(75));

            // Table lookup.
            {
                uint256 idx = 0;
                unchecked {
                    {
                        uint256 scale = isAtLeastE76 ? 1e73 : 1e72;
                        // Truncate the signed coefficient to what we can look
                        // up in the table.
                        // Slither false positive because the truncation is
                        // deliberate here.
                        //slither-disable-start divide-before-multiply
                        // scale is one of two possible values so won't truncate
                        // when cast.
                        // forge-lint: disable-next-line(unsafe-typecast)
                        x1Coefficient = signedCoefficient / int256(scale);
                        // slither-disable-end divide-before-multiply
                        // x1Coefficient is positive here so won't truncate when
                        // cast.
                        // forge-lint: disable-next-line(unsafe-typecast)
                        idx = uint256(x1Coefficient - 1000);
                        // scale is one of two possible values so won't truncate
                        // when cast.
                        // forge-lint: disable-next-line(unsafe-typecast)
                        x1Coefficient = x1Coefficient * int256(scale);
                        // Technically we only need to do this if we need to
                        // interpolate but it's cheaper to just do an `add`
                        // unconditionally than pay for an `if` and often also
                        // do the `add`.
                        // scale is one of two possible values so won't truncate
                        // when cast.
                        // forge-lint: disable-next-line(unsafe-typecast)
                        x2Coefficient = x1Coefficient + int256(scale);
                    }

                    y1Coefficient =
                        int256(1e72 * LibDecimalFloatImplementation.lookupLogTableVal(tablesDataContract, idx));
                    y2Coefficient = y1Coefficient;
                    // Only do the second lookup if we expect interpolation
                    // to need it.
                    if (x1Coefficient != signedCoefficient) {
                        y2Coefficient = idx == LOG_MANTISSA_LAST_INDEX
                            ? int256(1e76)
                            : int256(
                                1e72 * LibDecimalFloatImplementation.lookupLogTableVal(tablesDataContract, idx + 1)
                            );
                    }
                }
            }

            (signedCoefficient, exponent) = LibDecimalFloatImplementation.unitLinearInterpolation(
                x1Coefficient,
                signedCoefficient,
                x2Coefficient,
                exponent,
                y1Coefficient,
                y2Coefficient,
                LOG10_Y_EXPONENT
            );
            return add(signedCoefficient, exponent, powerOfTen, 0);
        }
        // This is a negative log. i.e. log(x) where 0 < x < 1.
        // log(x) = -log(1/x)
        else {
            (signedCoefficient, exponent) = inv(signedCoefficient, exponent);
            (signedCoefficient, exponent) = log10(tablesDataContract, signedCoefficient, exponent);
            return LibDecimalFloatImplementation.minus(signedCoefficient, exponent);
        }
    }
}
