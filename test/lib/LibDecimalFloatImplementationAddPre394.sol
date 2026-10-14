// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {ExponentOverflow} from "../../src/error/ErrDecimalFloat.sol";
import {
    ADD_MAX_EXPONENT_DIFF,
    MAXIMIZED_ZERO_SIGNED_COEFFICIENT,
    MAXIMIZED_ZERO_EXPONENT
} from "../../src/lib/implementation/LibDecimalFloatImplementation.sol";

/// `add` verbatim from `src/lib/implementation/LibDecimalFloatImplementation.sol`
/// at 8fcfeb3, before its overflow shed kept the carry (#394), with
/// `maximize` and its constants copied from the same commit, so it calls
/// nothing on the live library. Equivalence tests only.
/// EQUIVALENCE BASELINE ONLY, NEVER A VALUE ORACLE: agreeing with it says
/// nothing about a value. Expected values come from `LibExactFloat`.
library LibDecimalFloatImplementationAddPre394 {
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
        int256 shortfallA;
        int256 shortfallB;
        (signedCoefficientA, exponentA, shortfallA) = maximize(signedCoefficientA, exponentA);
        (signedCoefficientB, exponentB, shortfallB) = maximize(signedCoefficientB, exponentB);

        // We want A to represent the larger true exponent, which is the
        // exponent less the shortfall. If this is not the case then swap them.
        // A shortfall is only nonzero at the exponent floor, so comparing the
        // shortfalls breaks the tie there.
        if (exponentB > exponentA || shortfallB < shortfallA) {
            int256 tmp = signedCoefficientA;
            signedCoefficientA = signedCoefficientB;
            signedCoefficientB = tmp;

            tmp = exponentA;
            exponentA = exponentB;
            exponentB = tmp;

            tmp = shortfallA;
            shortfallA = shortfallB;
            shortfallB = tmp;
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
            // shortfallB >= shortfallA after the swap, and both are at most 76.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 shortfallDiff = uint256(shortfallB - shortfallA);
            // The early return here allows us to do unchecked pow on the
            // scaler and means we never revert due to overflow here. It is only
            // reachable with shortfallA == 0, as a nonzero shortfallA puts both
            // exponents at the floor.
            if (alignmentExponentDiff > ADD_MAX_EXPONENT_DIFF - shortfallDiff) {
                return (signedCoefficientA, exponentA);
            }
            // alignmentExponentDiff + shortfallDiff can't be greater than 76 so
            // will pow without truncation.
            // forge-lint: disable-next-line(unsafe-typecast)
            signedCoefficientB /= int256(10 ** (alignmentExponentDiff + shortfallDiff));
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

            // The sum's true exponent is below the floor, so shed the digits
            // the floor cannot hold. exponentA is the floor, or one above it
            // after an overflow.
            if (shortfallA != 0) {
                // The shed is in [0, 76].
                // forge-lint: disable-next-line(unsafe-typecast)
                signedCoefficientA /= int256(10 ** uint256(shortfallA - (exponentA - type(int256).min)));
                exponentA = type(int256).min;
            }
        }
        return (signedCoefficientA, exponentA);
    }

    // The helpers the copies above call, verbatim from the same commit, so
    // this baseline calls nothing on the live library.

    /// Maximizes a float's signed coefficient by increasing its magnitude
    /// and decreasing its exponent accordingly. Greatly simplified a lot of
    /// internal logic that involves comparing signed coefficients as integers,
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
    function maximize(int256 signedCoefficient, int256 exponent) private pure returns (int256, int256, int256) {
        unchecked {
            if (signedCoefficient == 0) {
                return (MAXIMIZED_ZERO_SIGNED_COEFFICIENT, MAXIMIZED_ZERO_EXPONENT, 0);
            }

            int256 maximizedExponent = exponent;
            assembly ("memory-safe") {
                // `sdiv` truncates toward zero, so `sdiv(c, 10^m)` is zero iff
                // |c| < 10^m, for either sign. Let s = 76 - digits(|c|), the
                // digits short of 76. Each step multiplies by 10^k iff
                // |c| < 10^(76 - k), that is s >= k, so |c| stays below 1e76
                // and inside int256 (max ~5.79e76). Steps of 38, 19 and 10
                // each about halve the range of s, then twos and a one finish.
                // Inside, s is in [1, 75]; outside, |c| >= 1e75 already.
                if iszero(sdiv(signedCoefficient, E75)) {
                    // s in [1, 75] -> [0, 37].
                    if iszero(sdiv(signedCoefficient, E38)) {
                        signedCoefficient := mul(signedCoefficient, E38)
                        maximizedExponent := sub(maximizedExponent, 38)
                    }
                    // s in [0, 37] -> [0, 18].
                    if iszero(sdiv(signedCoefficient, E57)) {
                        signedCoefficient := mul(signedCoefficient, E19)
                        maximizedExponent := sub(maximizedExponent, 19)
                    }
                    // s in [0, 18] -> [0, 9].
                    if iszero(sdiv(signedCoefficient, E66)) {
                        signedCoefficient := mul(signedCoefficient, E10)
                        maximizedExponent := sub(maximizedExponent, 10)
                    }
                    // s in [0, 9] -> [0, 1], in at most four rounds.
                    for {} iszero(sdiv(signedCoefficient, E74)) {} {
                        signedCoefficient := mul(signedCoefficient, 100)
                        maximizedExponent := sub(maximizedExponent, 2)
                    }
                    // s in [0, 1] -> 0: |c| in [1e75, 1e76).
                    if iszero(sdiv(signedCoefficient, E75)) {
                        signedCoefficient := mul(signedCoefficient, 10)
                        maximizedExponent := sub(maximizedExponent, 1)
                    }
                }
            }

            // One more order of magnitude, if it fits. 10 c fits int256 iff
            // |c| <= TIMES_TEN_MAX (T, ~5.79e75) for either sign, as
            // 10 T = 2^255 - 8. Adding T maps [-T, T] onto [0, 2T], and any
            // other int256 lands above 2T as uint256 without wrapping, so one
            // comparison covers both signs. A fit takes |c| from [1e75, T]
            // into [1e76, 10 T].
            // forge-lint: disable-next-line(unsafe-typecast)
            if (uint256(signedCoefficient) + TIMES_TEN_MAX < TIMES_TEN_SPAN) {
                signedCoefficient *= 10;
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
