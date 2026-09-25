// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Float, LibDecimalFloat} from "src/lib/LibDecimalFloat.sol";

contract LibDecimalFloatAgreeTest is Test {
    using LibDecimalFloat for Float;

    function f(int256 signedCoefficient, int256 exponent) internal pure returns (Float) {
        return LibDecimalFloat.packLossless(signedCoefficient, exponent);
    }

    function minNegative() internal pure returns (Float) {
        return LibDecimalFloat.packLossless(type(int224).min, type(int32).max);
    }

    function maxPositive() internal pure returns (Float) {
        return LibDecimalFloat.packLossless(type(int224).max, type(int32).max);
    }

    /// The proportional tolerance is of the LARGER MAGNITUDE of the two
    /// extremes, so with positive values it is a proportion of the highest.
    ///
    /// 100 - 99 == 1 == 0.01 * 100, so this sits exactly on the limit and is
    /// accepted, because the check is `<=`. Anchoring on the lower value would
    /// give 0.01 * 99 == 0.99 and reject it, so these distinguish the two
    /// anchors rather than merely exercising one.
    function testAgreeProportionalBoundary() external pure {
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, -2), f(99, 0), f(100, 0)));
        assertFalse(LibDecimalFloat.agree(f(0, 0), f(1, -2), f(98999, -3), f(100, 0)));
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, -2), f(99001, -3), f(100, 0)));
    }

    /// The absolute tolerance is in the same units as the values and does not
    /// scale with them.
    function testAgreeAbsoluteBoundary() external pure {
        assertTrue(LibDecimalFloat.agree(f(1, 0), f(0, 0), f(100, 0), f(101, 0)));
        assertFalse(LibDecimalFloat.agree(f(1, 0), f(0, 0), f(100, 0), f(101001, -3)));
        assertTrue(LibDecimalFloat.agree(f(1, 0), f(0, 0), f(100, 0), f(100999, -3)));
    }

    /// The limit is the LARGER of the two terms, not their sum.
    ///
    /// With an absolute tolerance of 0.5, a proportional tolerance of 0.01 and
    /// a highest of 100, the larger term is 1 and the sum would be 1.5. A
    /// spread of 1.2 falls between them, so it distinguishes the two forms
    /// rather than merely exercising one.
    function testAgreeLimitIsTheLargerNotTheSum() external pure {
        assertTrue(LibDecimalFloat.agree(f(5, -1), f(1, -2), f(99, 0), f(100, 0)));
        assertFalse(LibDecimalFloat.agree(f(5, -1), f(1, -2), f(988, -1), f(100, 0)));
    }

    /// Either tolerance alone carries the check when the other is zero.
    function testAgreeOneToleranceZero() external pure {
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, -2), f(99, 0), f(100, 0)));
        assertTrue(LibDecimalFloat.agree(f(1, 0), f(0, 0), f(100, 0), f(101, 0)));
    }

    /// The magnitude is taken, so negatives behave as positives reflected
    /// through zero rather than being rejected outright.
    function testAgreeNegativeValues() external pure {
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, -2), f(-100, 0), f(-99, 0)));
        assertFalse(LibDecimalFloat.agree(f(0, 0), f(1, -2), f(-100, 0), f(-98999, -3)));
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, -2), f(-100, 0), f(-100, 0)));
    }

    /// Values symmetric about zero are the furthest apart anything can be
    /// relative to its own magnitude: the spread is twice the anchor, so a
    /// proportional tolerance has to reach 200%.
    function testAgreeSymmetricAboutZero() external pure {
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(2, 0), f(-1, 0), f(1, 0)));
        assertFalse(LibDecimalFloat.agree(f(0, 0), f(199, -2), f(-1, 0), f(1, 0)));
        assertTrue(LibDecimalFloat.agree(f(2, 0), f(0, 0), f(-1, 0), f(1, 0)));
    }

    /// WHY BOTH TOLERANCES EXIST. A proportional tolerance collapses as the
    /// values approach zero, because the quantity it is a proportion of
    /// shrinks with them. The absolute term is what covers that region.
    function testAgreeNearZero() external pure {
        assertFalse(LibDecimalFloat.agree(f(0, 0), f(1, -2), f(-1, -3), f(1, -3)));
        assertTrue(LibDecimalFloat.agree(f(1, -2), f(0, 0), f(-1, -3), f(1, -3)));
    }

    /// THE REASON THIS CANNOT BE COMPOSED FROM THE PUBLIC SURFACE.
    ///
    /// Both `abs` and `sub` revert `ExponentOverflow` on these values, because
    /// the exponent is already at its maximum and neither the magnitude of the
    /// most negative coefficient nor the spread across the whole range fits a
    /// packed value. `agree` answers instead of reverting, which is only
    /// possible by staying below that surface.
    function testAgreeAcrossTheWholeRange() external pure {
        // A spread this wide is not within a 1% proportional tolerance.
        assertFalse(LibDecimalFloat.agree(f(0, 0), f(1, -2), minNegative(), maxPositive()));
        // The most negative value against itself has a zero spread, so it
        // agrees. The packed `abs` cannot even be asked this question.
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, -2), minNegative(), minNegative()));
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, -2), maxPositive(), maxPositive()));
    }

    /// Identical values agree under any non negative tolerance, and a zero
    /// spread is the only thing two zero tolerances accept.
    function testAgreeZeroSpread() external pure {
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(0, 0), f(100, 0), f(100, 0)));
        assertFalse(LibDecimalFloat.agree(f(0, 0), f(0, 0), f(100, 0), f(101, 0)));
    }

    /// The comparison is numerical, so the representation of the tolerances
    /// and the values does not change the answer.
    function testAgreeNumericalEquality() external pure {
        // 0.01 written three ways, against the same boundary.
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(1, -2), f(99, 0), f(100, 0)));
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(10, -3), f(99, 0), f(100, 0)));
        assertTrue(LibDecimalFloat.agree(f(0, 0), f(100, -4), f(990, -1), f(1000, -1)));
    }

    /// A tolerance at the top of the range accepts rather than reverting: the
    /// multiplication scales the coefficient down and raises the exponent
    /// instead of overflowing, and nothing is packed back.
    function testAgreeExtremeTolerance() external pure {
        assertTrue(LibDecimalFloat.agree(f(0, 0), maxPositive(), f(1, 0), f(2, 0)));
        assertTrue(LibDecimalFloat.agree(maxPositive(), f(0, 0), f(1, 0), f(2, 0)));
        assertTrue(LibDecimalFloat.agree(f(0, 0), maxPositive(), minNegative(), maxPositive()));
    }
}
