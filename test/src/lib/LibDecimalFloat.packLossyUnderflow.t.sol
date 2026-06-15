// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, ExponentOverflow, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std-1.16.1/src/Test.sol";

/// Adversarial coverage for `packLossy`'s underflow and coefficient-truncation
/// paths. The tests here derive an INDEPENDENT oracle for the normalisation
/// (naive "divide by ten until the coefficient fits int224") and the
/// underflow/overflow classification, then assert the production output matches
/// that oracle at the int224 / int32 boundaries the happy-path tests avoid.
contract LibDecimalFloatPackLossyUnderflowTest is Test {
    int256 constant INT224_MAX = int256(type(int224).max);
    int256 constant INT224_MIN = int256(type(int224).min);
    int256 constant INT32_MAX = int256(type(int32).max);
    int256 constant INT32_MIN = int256(type(int32).min);

    function packLossyExternal(int256 signedCoefficient, int256 exponent) external pure returns (Float, bool) {
        return LibDecimalFloat.packLossy(signedCoefficient, exponent);
    }

    /// Independent oracle. Mirrors the DOCUMENTED contract of `packLossy` but is
    /// implemented from scratch (naive divide-by-ten loop, no 1e72/1e5
    /// shortcut), so it cannot share a bug with the production shortcut.
    ///
    /// Returns the expected unpacked (coefficient, exponent), whether the result
    /// is the underflow zero, and the expected `lossless` flag.
    ///
    /// Restricted to a domain where the production unchecked exponent
    /// arithmetic cannot wrap int256 (|exponent| well below int256 limits), so
    /// every transition is exercised without leaving the well-defined region.
    function oracle(int256 signedCoefficient, int256 exponent)
        internal
        pure
        returns (int256 expCoeff, int256 expExponent, bool expIsZero, bool expLossless, bool expOverflow)
    {
        // lossless iff the ORIGINAL coefficient already fits int224.
        bool fits = signedCoefficient <= INT224_MAX && signedCoefficient >= INT224_MIN;
        expLossless = fits;

        if (fits) {
            if (signedCoefficient == 0) {
                // Zero is always the lossless zero, exponent ignored.
                return (0, 0, true, true, false);
            }
        } else {
            // Naive normalisation: divide by ten until it fits, bumping exponent.
            while (signedCoefficient > INT224_MAX || signedCoefficient < INT224_MIN) {
                signedCoefficient /= 10;
                exponent += 1;
            }
        }

        // Classify by whether the (possibly bumped) exponent fits int32.
        if (exponent > INT32_MAX || exponent < INT32_MIN) {
            if (exponent < 0) {
                return (0, 0, true, false, false);
            }
            return (0, 0, false, false, true);
        }

        return (signedCoefficient, exponent, signedCoefficient == 0, expLossless, false);
    }

    /// Drive the production function and compare to the oracle.
    function checkAgainstOracle(int256 signedCoefficient, int256 exponent) internal {
        (int256 expCoeff, int256 expExponent, bool expIsZero, bool expLossless, bool expOverflow) =
            oracle(signedCoefficient, exponent);

        if (expOverflow) {
            vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficient, exponent));
            this.packLossyExternal(signedCoefficient, exponent);
            return;
        }

        (Float float, bool lossless) = LibDecimalFloat.packLossy(signedCoefficient, exponent);
        assertEq(lossless, expLossless, "lossless flag");

        if (expIsZero) {
            assertEq(Float.unwrap(float), Float.unwrap(LibDecimalFloat.FLOAT_ZERO), "expected zero float");
            return;
        }

        assertTrue(Float.unwrap(float) != Float.unwrap(LibDecimalFloat.FLOAT_ZERO), "unexpected zero float");
        (int256 outCoeff, int256 outExponent) = LibDecimalFloat.unpack(float);
        assertEq(outCoeff, expCoeff, "coefficient");
        assertEq(outExponent, expExponent, "exponent");
    }

    /// Fuzz the coefficient across the FULL int256 range (so the int224-overflow
    /// normalisation loop and 1e72/1e5 shortcut are both exercised) and the
    /// exponent across a wide band straddling int32.min and int32.max (so the
    /// underflow-zero, in-range and overflow-revert transitions all fire),
    /// while staying clear of the int256 wrap region.
    function testPackLossyOracleFullCoefficient(int256 signedCoefficient, int256 exponent) external {
        // Band around int32 limits, plus headroom for the at-most ~77 exponent
        // bumps the normalisation can add. Far from int256 wrap.
        exponent = bound(exponent, INT32_MIN - 200, INT32_MAX + 200);
        checkAgainstOracle(signedCoefficient, exponent);
    }

    /// Focus the fuzz on coefficients just over the int224 boundary (one or two
    /// digits of truncation) crossed with exponents straddling int32.min, so the
    /// "rescale lifts the exponent back over the floor" window is hammered.
    function testPackLossyOracleNearInt224Boundary(int256 coeffOffset, int256 exponent) external {
        // Multiply int224.max by a small factor to stay just above the boundary
        // (1..1e6 OOM range), both signs.
        coeffOffset = bound(coeffOffset, 1, 1_000_000);
        int256 signedCoefficient = (INT224_MAX + 1) * coeffOffset;
        if (uint256(exponent) % 2 == 0) {
            signedCoefficient = -signedCoefficient;
        }
        exponent = bound(exponent, INT32_MIN - 50, INT32_MIN + 50);
        checkAgainstOracle(signedCoefficient, exponent);
    }

    /// Concrete: exactly at int224.max the coefficient fits, so an exponent one
    /// below int32.min must underflow to the lossy zero (NOT truncate the
    /// coefficient, since it already fits — the loop never runs).
    function testPackLossyInt224MaxExactUnderflow() external pure {
        (Float float, bool lossless) = LibDecimalFloat.packLossy(INT224_MAX, INT32_MIN - 1);
        assertFalse(lossless, "lossless");
        assertEq(Float.unwrap(float), Float.unwrap(LibDecimalFloat.FLOAT_ZERO), "zero");
    }

    /// Concrete: int224.max at exactly int32.min is in-range and lossless.
    function testPackLossyInt224MaxAtFloor() external pure {
        (Float float, bool lossless) = LibDecimalFloat.packLossy(INT224_MAX, INT32_MIN);
        assertTrue(lossless, "lossless");
        (int256 c, int256 e) = LibDecimalFloat.unpack(float);
        assertEq(c, INT224_MAX, "coeff");
        assertEq(e, INT32_MIN, "exp");
    }

    /// Concrete: int224.min (most negative coefficient) fits losslessly and
    /// round-trips at the int32 floor. Negative-boundary twin of the above.
    function testPackLossyInt224MinAtFloor() external pure {
        (Float float, bool lossless) = LibDecimalFloat.packLossy(INT224_MIN, INT32_MIN);
        assertTrue(lossless, "lossless");
        (int256 c, int256 e) = LibDecimalFloat.unpack(float);
        assertEq(c, INT224_MIN, "coeff");
        assertEq(e, INT32_MIN, "exp");
    }

    /// Concrete: int224.min one below the floor underflows to lossy zero.
    function testPackLossyInt224MinUnderflow() external pure {
        (Float float, bool lossless) = LibDecimalFloat.packLossy(INT224_MIN, INT32_MIN - 1);
        assertFalse(lossless, "lossless");
        assertEq(Float.unwrap(float), Float.unwrap(LibDecimalFloat.FLOAT_ZERO), "zero");
    }

    /// DOCUMENTED EDGE (out of the reachable public domain): when the input
    /// exponent is itself near int256.max AND the coefficient does not fit
    /// int224, the unchecked `exponent += 5` / `++exponent` normalisation wraps
    /// int256 to a very large NEGATIVE number, so the `int32(exponent) != exponent`
    /// check sees a negative exponent and returns the underflow sentinel
    /// `(FLOAT_ZERO, false)` — even though the true value is an enormous OVERFLOW.
    ///
    /// This cannot be reached from the public arithmetic/parse surface: every
    /// packed `Float` carries an int32 exponent, and arithmetic only sums/offsets
    /// those, so exponents fed to `packLossy` stay within ~int33 magnitude — many
    /// orders below the int256 wrap point. The existing overflow test deliberately
    /// caps the exponent at `int256.max - 77` to stay clear of this region.
    ///
    /// This test PINS the current behaviour so a future change to the
    /// normalisation arithmetic is caught; it is NOT asserting that returning the
    /// underflow sentinel for an overflow is "correct".
    function testPackLossyInt256MaxExponentWrapIsUnderflowSentinel() external pure {
        // Coefficient way past int224 so the normalisation loop runs and the
        // exponent gets bumped (and thus wraps from int256.max).
        (Float a, bool losslessA) = LibDecimalFloat.packLossy(type(int256).max, type(int256).max);
        assertFalse(losslessA, "huge coeff lossless");
        assertEq(Float.unwrap(a), Float.unwrap(LibDecimalFloat.FLOAT_ZERO), "huge coeff -> sentinel");

        // One past int224 (single loop iteration) at int256.max also wraps.
        (Float b, bool losslessB) = LibDecimalFloat.packLossy(INT224_MAX + 1, type(int256).max);
        assertFalse(losslessB, "boundary coeff lossless");
        assertEq(Float.unwrap(b), Float.unwrap(LibDecimalFloat.FLOAT_ZERO), "boundary coeff -> sentinel");
    }

    /// NO-COLLISION / injectivity near the boundaries. Two numerically-distinct
    /// in-range Floats (both fit int224, both within int32, neither the lossy
    /// zero) must be byte-UNEQUAL after packing. Fuzzed at the int224/int32
    /// extremes where the high coefficient bits abut the exponent bits.
    function testPackLossyNoCollisionAtBoundaries(
        int224 coefficientA,
        int32 exponentA,
        int224 coefficientB,
        int32 exponentB
    ) external pure {
        // Neither zero (zero collapses to FLOAT_ZERO regardless of exponent,
        // which is a legitimate non-injective case for numerically-equal zeros).
        vm.assume(coefficientA != 0);
        vm.assume(coefficientB != 0);
        // Numerically distinct as (coefficient, exponent) pairs.
        vm.assume(!(coefficientA == coefficientB && exponentA == exponentB));

        (Float a, bool losslessA) = LibDecimalFloat.packLossy(coefficientA, exponentA);
        (Float b, bool losslessB) = LibDecimalFloat.packLossy(coefficientB, exponentB);
        // In-range int224/int32 inputs always pack losslessly.
        assertTrue(losslessA, "losslessA");
        assertTrue(losslessB, "losslessB");

        assertTrue(Float.unwrap(a) != Float.unwrap(b), "distinct in-range floats collided");
    }

    /// Pin the boundary of the negative-exponent underflow predicate itself:
    /// a coefficient of magnitude 1 (always fits int224) with exponent exactly
    /// int32.min is in-range; one step below underflows. This isolates the
    /// `int32(exponent) != exponent` + `exponent < 0` branch from the
    /// coefficient loop.
    function testPackLossyUnitCoefficientFloorBoundary() external pure {
        (Float floor, bool losslessFloor) = LibDecimalFloat.packLossy(1, INT32_MIN);
        assertTrue(losslessFloor, "floor lossless");
        (int256 c, int256 e) = LibDecimalFloat.unpack(floor);
        assertEq(c, 1, "floor coeff");
        assertEq(e, INT32_MIN, "floor exp");

        (Float under, bool losslessUnder) = LibDecimalFloat.packLossy(1, INT32_MIN - 1);
        assertFalse(losslessUnder, "under lossless");
        assertEq(Float.unwrap(under), Float.unwrap(LibDecimalFloat.FLOAT_ZERO), "under zero");
    }

    /// Concrete coverage of the `>= 1e72` fast-path shortcut (divide by 1e5 /
    /// bump exponent by 5) followed by the residual divide-by-ten loop. A
    /// coefficient just at int256.max exercises the branch deterministically
    /// (the full-range fuzz hits it too, but this pins it regardless of seed).
    /// The shortcut must compose with truncated division exactly like the naive
    /// loop, so the result matches the oracle.
    function testPackLossyLargeCoefficientShortcut() external {
        // int256.max ~ 5.78e76, well above 1e72, both signs.
        checkAgainstOracle(type(int256).max, 0);
        checkAgainstOracle(type(int256).min + 1, 0);
        // A clean power of ten above 1e72 so the truncation is exact and the
        // shortcut's `exponent += 5` bookkeeping is pinned to a known value.
        checkAgainstOracle(int256(1e73), 7);
        checkAgainstOracle(-int256(1e73), 7);
    }

    /// Pin the positive overflow boundary mirror: unit coefficient at exactly
    /// int32.max is in-range; one above reverts ExponentOverflow.
    function testPackLossyUnitCoefficientCeilBoundary() external {
        (Float ceil, bool losslessCeil) = LibDecimalFloat.packLossy(1, INT32_MAX);
        assertTrue(losslessCeil, "ceil lossless");
        (int256 c, int256 e) = LibDecimalFloat.unpack(ceil);
        assertEq(c, 1, "ceil coeff");
        assertEq(e, INT32_MAX, "ceil exp");

        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(1), INT32_MAX + 1));
        this.packLossyExternal(1, INT32_MAX + 1);
    }
}
