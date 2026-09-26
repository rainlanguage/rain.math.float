// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

/// `lt`, `gt`, `gte` and `min` on unpacked values. `lte` and `max` have their
/// own files; these are the rest of the set, so the unpacked surface carries
/// every comparison the packed surface does rather than a subset of them.
contract LibDecimalFloatImplementationComparisonsTest is Test {
    function lt(int256 cA, int256 eA, int256 cB, int256 eB) internal pure returns (bool) {
        return LibDecimalFloatImplementation.lt(cA, eA, cB, eB);
    }

    function gt(int256 cA, int256 eA, int256 cB, int256 eB) internal pure returns (bool) {
        return LibDecimalFloatImplementation.gt(cA, eA, cB, eB);
    }

    function gte(int256 cA, int256 eA, int256 cB, int256 eB) internal pure returns (bool) {
        return LibDecimalFloatImplementation.gte(cA, eA, cB, eB);
    }

    function lte(int256 cA, int256 eA, int256 cB, int256 eB) internal pure returns (bool) {
        return LibDecimalFloatImplementation.lte(cA, eA, cB, eB);
    }

    function eq(int256 cA, int256 eA, int256 cB, int256 eB) internal pure returns (bool) {
        return LibDecimalFloatImplementation.eq(cA, eA, cB, eB);
    }

    /// Same exponent reduces to comparing coefficients.
    function testSameExponent() external pure {
        assertTrue(lt(1, 0, 2, 0));
        assertFalse(lt(2, 0, 2, 0));
        assertTrue(gt(3, 0, 2, 0));
        assertFalse(gt(2, 0, 2, 0));
        assertTrue(gte(2, 0, 2, 0));
        assertTrue(gte(3, 0, 2, 0));
        assertFalse(gte(1, 0, 2, 0));
    }

    /// THE POINT OF THE FUNCTIONS: different exponents are rescaled before
    /// comparing, so a smaller coefficient can be the larger value.
    function testDifferentExponents() external pure {
        // 1e1 == 10 > 9e0, despite the coefficient being smaller.
        assertTrue(gt(1, 1, 9, 0));
        assertFalse(lt(1, 1, 9, 0));
        assertTrue(lt(9, 0, 1, 1));
        // 1e-1 == 0.1 < 1e0.
        assertTrue(lt(1, -1, 1, 0));
        assertTrue(gt(1, 0, 1, -1));
    }

    /// Numerically equal values are neither less nor greater, whichever way
    /// they are packed, and the inclusive forms hold both directions.
    function testNumericallyEqual() external pure {
        assertFalse(lt(100, 0, 1, 2));
        assertFalse(gt(100, 0, 1, 2));
        assertTrue(gte(100, 0, 1, 2));
        assertTrue(gte(1, 2, 100, 0));
        assertFalse(lt(10, 1, 100, 0));
        assertFalse(gt(10, 1, 100, 0));
    }

    /// Nothing is less than or greater than itself; every value is >= itself.
    function testIrreflexive(int256 signedCoefficient, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, type(int224).min, type(int224).max);
        exponent = bound(exponent, -50, 50);
        assertFalse(lt(signedCoefficient, exponent, signedCoefficient, exponent));
        assertFalse(gt(signedCoefficient, exponent, signedCoefficient, exponent));
        assertTrue(gte(signedCoefficient, exponent, signedCoefficient, exponent));
    }

    /// `gt` is `lt` with the operands swapped, and `gte` is `lte` swapped, for
    /// every pair. This is what pins the four to one another rather than each
    /// being independently plausible.
    function testDualities(int256 cA, int256 eA, int256 cB, int256 eB) external pure {
        cA = bound(cA, type(int224).min, type(int224).max);
        cB = bound(cB, type(int224).min, type(int224).max);
        eA = bound(eA, -50, 50);
        eB = bound(eB, -50, 50);

        assertEq(gt(cA, eA, cB, eB), lt(cB, eB, cA, eA));
        assertEq(gte(cA, eA, cB, eB), lte(cB, eB, cA, eA));
        // Exactly one of <, ==, > holds.
        assertEq(lt(cA, eA, cB, eB), !gte(cA, eA, cB, eB));
        assertEq(gt(cA, eA, cB, eB), !lte(cA, eA, cB, eB));
        // The inclusive forms are the strict form or equality.
        assertEq(lte(cA, eA, cB, eB), lt(cA, eA, cB, eB) || eq(cA, eA, cB, eB));
        assertEq(gte(cA, eA, cB, eB), gt(cA, eA, cB, eB) || eq(cA, eA, cB, eB));
    }

    /// `lt` is transitive across rescaling.
    function testLtTransitive(int256 cA, int256 cB, int256 cC) external pure {
        cA = bound(cA, -1e30, 1e30);
        cB = bound(cB, -1e30, 1e30);
        cC = bound(cC, -1e30, 1e30);
        // Deliberately different exponents so rescaling is exercised.
        if (lt(cA, 3, cB, 0) && lt(cB, 0, cC, -3)) {
            assertTrue(lt(cA, 3, cC, -3));
        }
    }

    /// `min` returns an operand, and one that is <= both.
    function testMin(int256 cA, int256 eA, int256 cB, int256 eB) external pure {
        cA = bound(cA, type(int224).min, type(int224).max);
        cB = bound(cB, type(int224).min, type(int224).max);
        eA = bound(eA, -50, 50);
        eB = bound(eB, -50, 50);

        (int256 c, int256 e) = LibDecimalFloatImplementation.min(cA, eA, cB, eB);

        // It is one of the two operands, unchanged.
        assertTrue((c == cA && e == eA) || (c == cB && e == eB));
        // And it is no greater than either.
        assertTrue(lte(c, e, cA, eA));
        assertTrue(lte(c, e, cB, eB));
    }

    /// `min` and `max` pick opposite ends of the same pair: the pair of results
    /// is the pair of inputs, whichever order they arrive in.
    function testMinMaxPartitionThePair(int256 cA, int256 eA, int256 cB, int256 eB) external pure {
        cA = bound(cA, type(int224).min, type(int224).max);
        cB = bound(cB, type(int224).min, type(int224).max);
        eA = bound(eA, -50, 50);
        eB = bound(eB, -50, 50);

        (int256 lowC, int256 lowE) = LibDecimalFloatImplementation.min(cA, eA, cB, eB);
        (int256 highC, int256 highE) = LibDecimalFloatImplementation.max(cA, eA, cB, eB);

        assertTrue(lte(lowC, lowE, highC, highE));
        // Numerically the multiset {min, max} is the multiset {A, B}.
        assertTrue(
            (eq(lowC, lowE, cA, eA) && eq(highC, highE, cB, eB)) || (eq(lowC, lowE, cB, eB) && eq(highC, highE, cA, eA))
        );
    }

    /// Ties return B, matching `max`, so the choice is stable and documented
    /// rather than incidental.
    function testMinTieReturnsB() external pure {
        (int256 c, int256 e) = LibDecimalFloatImplementation.min(100, 0, 1, 2);
        assertEq(c, 1);
        assertEq(e, 2);
    }
}
