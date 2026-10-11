// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";
import {LibTestRegion} from "test/lib/LibTestRegion.sol";

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
        assertFalse(lt(signedCoefficient, exponent, signedCoefficient, exponent));
        assertFalse(gt(signedCoefficient, exponent, signedCoefficient, exponent));
        assertTrue(gte(signedCoefficient, exponent, signedCoefficient, exponent));
    }

    /// Every comparison is the exact order of the pair.
    function testAgainstExactOrder(int256 cA, int256 eA, int256 cB, int256 eB) external pure {
        checkExactOrder(cA, eA, cB, eB);
    }

    /// Every comparison is the exact order of the pair, with coefficients of
    /// every digit count at exponents within 76 of each other, where the
    /// comparison rescales.
    function testAgainstExactOrderRescaled(int256 cA, uint256 dropA, int256 eA, int256 cB, uint256 dropB, int256 offset)
        external
        pure
    {
        checkExactOrder(
            LibTestRegion.anyDigits(cA, dropA),
            eA,
            LibTestRegion.anyDigits(cB, dropB),
            LibTestRegion.nearExponent(eA, offset)
        );
    }

    function checkExactOrder(int256 cA, int256 eA, int256 cB, int256 eB) internal pure {
        int256 order = LibTestExactDecimal.cmpParts(cA, eA, cB, eB);
        assertEq(lt(cA, eA, cB, eB), order < 0, "lt");
        assertEq(lte(cA, eA, cB, eB), order <= 0, "lte");
        assertEq(gt(cA, eA, cB, eB), order > 0, "gt");
        assertEq(gte(cA, eA, cB, eB), order >= 0, "gte");
        assertEq(eq(cA, eA, cB, eB), order == 0, "eq");
    }

    /// `lt` is transitive across rescaling.
    function testLtTransitive(int256 cA, int256 eA, int256 cB, int256 eB, int256 cC, int256 eC) external pure {
        checkLtTransitive(cA, eA, cB, eB, cC, eC);
    }

    /// `lt` is transitive with coefficients of every digit count at exponents
    /// within 76 of each other, where every comparison rescales.
    function testLtTransitiveRescaled(
        int256 cA,
        int256 cB,
        int256 cC,
        uint256 drops,
        int256 eB,
        int256 offsetA,
        int256 offsetC
    ) external pure {
        int256 eA = LibTestRegion.nearExponent(eB, offsetA % 39);
        int256 eC = LibTestRegion.nearExponent(eB, offsetC % 39);
        checkLtTransitive(
            LibTestRegion.anyDigits(cA, drops),
            eA,
            LibTestRegion.anyDigits(cB, drops / 77),
            eB,
            LibTestRegion.anyDigits(cC, drops / 77 / 77),
            eC
        );
    }

    function checkLtTransitive(int256 cA, int256 eA, int256 cB, int256 eB, int256 cC, int256 eC) internal pure {
        if (lt(cA, eA, cB, eB) && lt(cB, eB, cC, eC)) {
            assertTrue(lt(cA, eA, cC, eC));
        }
    }

    /// `min` returns A, unchanged, when A is exactly below B, else B.
    function testMin(int256 cA, int256 eA, int256 cB, int256 eB) external pure {
        (int256 c, int256 e) = LibDecimalFloatImplementation.min(cA, eA, cB, eB);
        bool isA = LibTestExactDecimal.cmpParts(cA, eA, cB, eB) < 0;
        assertEq(c, isA ? cA : cB, "coefficient");
        assertEq(e, isA ? eA : eB, "exponent");
    }

    /// `min` and `max` pick opposite ends of the same pair, both taking B on
    /// a tie.
    function testMinMaxPartitionThePair(int256 cA, int256 eA, int256 cB, int256 eB) external pure {
        (int256 lowC, int256 lowE) = LibDecimalFloatImplementation.min(cA, eA, cB, eB);
        (int256 highC, int256 highE) = LibDecimalFloatImplementation.max(cA, eA, cB, eB);

        int256 order = LibTestExactDecimal.cmpParts(cA, eA, cB, eB);
        assertEq(lowC, order < 0 ? cA : cB, "min coefficient");
        assertEq(lowE, order < 0 ? eA : eB, "min exponent");
        assertEq(highC, order > 0 ? cA : cB, "max coefficient");
        assertEq(highE, order > 0 ? eA : eB, "max exponent");
    }

    /// Ties return B, matching `max`, so the choice is stable and documented
    /// rather than incidental.
    function testMinTieReturnsB() external pure {
        (int256 c, int256 e) = LibDecimalFloatImplementation.min(100, 0, 1, 2);
        assertEq(c, 1);
        assertEq(e, 2);
    }
}
