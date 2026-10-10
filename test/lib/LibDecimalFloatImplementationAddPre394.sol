// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {ExponentOverflow} from "src/error/ErrDecimalFloat.sol";
import {
    LibDecimalFloatImplementation,
    ADD_MAX_EXPONENT_DIFF
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

/// `add` verbatim from `src/lib/implementation/LibDecimalFloatImplementation.sol`
/// at 8fcfeb3, before its overflow shed kept the carry (#394). `maximize` is
/// called on the live library. Equivalence tests only.
library LibDecimalFloatImplementationAddPre394 {
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
        (signedCoefficientA, exponentA, shortfallA) =
            LibDecimalFloatImplementation.maximize(signedCoefficientA, exponentA);
        (signedCoefficientB, exponentB, shortfallB) =
            LibDecimalFloatImplementation.maximize(signedCoefficientB, exponentB);

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
}
