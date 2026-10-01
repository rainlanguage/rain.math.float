// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, ExponentOverflow, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";

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
    /// implemented from scratch (one naive divide-by-ten loop driven by BOTH
    /// bounds, no 1e72/1e5 shortcut, no single-shot power-of-ten division, and
    /// `lossless` tracked per digit rather than recovered by a modulo at the
    /// end), so it cannot share a bug with the production arithmetic.
    ///
    /// The contract: divide the coefficient by ten (towards zero) and raise the
    /// exponent by one until the coefficient fits int224 and the exponent is at
    /// or above int32.min. A coefficient that reaches zero is the underflow
    /// zero. An exponent above int32.max is an overflow revert. The pack is
    /// lossless iff every digit shed was a zero.
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
        if (signedCoefficient == 0) {
            // Zero is always the lossless zero, exponent ignored.
            // The literal is the bool this function returns, not a condition operand.
            //forge-lint: disable-next-line(boolean-cst)
            return (0, 0, true, true, false);
        }

        // Naive normalisation: one digit at a time, for as long as EITHER bound
        // is violated, tracking whether a non-zero digit was ever shed.
        // The literal is the bool this function returns, not a condition operand.
        //forge-lint: disable-next-line(boolean-cst)
        expLossless = true;
        while (signedCoefficient > INT224_MAX || signedCoefficient < INT224_MIN || exponent < INT32_MIN) {
            if (signedCoefficient % 10 != 0) {
                // The literal is the bool this function returns, not a condition operand.
                //forge-lint: disable-next-line(boolean-cst)
                expLossless = false;
            }
            signedCoefficient /= 10;
            exponent += 1;
            if (signedCoefficient == 0) {
                // Every digit shed: the underflow zero, never lossless (the
                // input was non-zero).
                // The literal is the bool this function returns, not a condition operand.
                //forge-lint: disable-next-line(boolean-cst)
                return (0, 0, true, false, false);
            }
        }

        // Shedding only raises the exponent, so overflow is decided by where it
        // ended up.
        if (exponent > INT32_MAX) {
            // The literal is the bool this function returns, not a condition operand.
            //forge-lint: disable-next-line(boolean-cst)
            return (0, 0, false, false, true);
        }

        // The literal is the bool this function returns, not a condition operand.
        //forge-lint: disable-next-line(boolean-cst)
        return (signedCoefficient, exponent, false, expLossless, false);
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
        // Casting to `uint256` is safe because parity survives the two's complement
        // reinterpretation, and parity is all this reads.
        //forge-lint: disable-next-line(unsafe-typecast)
        if (uint256(exponent) % 2 == 0) {
            signedCoefficient = -signedCoefficient;
        }
        exponent = bound(exponent, INT32_MIN - 50, INT32_MIN + 50);
        checkAgainstOracle(signedCoefficient, exponent);
    }

    /// Concrete: exactly at int224.max the coefficient fits, so the int224 loop
    /// never runs; an exponent one below int32.min is met by shedding one
    /// digit instead. int224.max does not end in zero, so the pack is lossy,
    /// but the magnitude survives: the result is the truncated coefficient at
    /// the floor, not the underflow zero.
    function testPackLossyInt224MaxOneBelowFloorShedsOneDigit() external pure {
        (Float float, bool lossless) = LibDecimalFloat.packLossy(INT224_MAX, INT32_MIN - 1);
        assertFalse(lossless, "lossless");
        (int256 c, int256 e) = LibDecimalFloat.unpack(float);
        assertEq(c, INT224_MAX / 10, "coeff");
        assertEq(e, INT32_MIN, "exp");
    }

    /// Shedding trailing zeros to reach the floor is free: for any non-zero
    /// `m` and any `z`, `m * 10^z` at `int32.min - z` packs losslessly to
    /// exactly `(m, int32.min)`. This is the general form of the issue #271
    /// counterexample, where maximisation had multiplied a value AT the floor
    /// by `1e75` and lowered its exponent to match.
    function testPackLossyTrailingZerosBelowFloorAreFree(int256 m, uint256 z) external pure {
        // |m| <= 1e16 and z <= 60 keeps m * 10^z inside int256 (<= 1e76).
        m = bound(m, -1e16, 1e16);
        vm.assume(m != 0);
        z = bound(z, 0, 60);
        // Safe: 1e76 fits int256.
        //forge-lint: disable-next-line(unsafe-typecast)
        int256 signedCoefficient = m * int256(10 ** z);
        // Safe: z <= 60.
        //forge-lint: disable-next-line(unsafe-typecast)
        int256 exponent = INT32_MIN - int256(z);

        (Float float, bool lossless) = LibDecimalFloat.packLossy(signedCoefficient, exponent);
        assertTrue(lossless, "lossless");
        (int256 c, int256 e) = LibDecimalFloat.unpack(float);
        assertEq(c, m, "coeff");
        assertEq(e, INT32_MIN, "exp");
    }

    /// Shedding a significant digit to reach the floor is lossy but keeps the
    /// magnitude: a coefficient whose last digit is non-zero at `int32.min - d`
    /// packs to the coefficient with its last `d` digits dropped, at the floor,
    /// for as long as any digit remains. Once `d` reaches the digit count the
    /// value is below any representable Float and the pack is the underflow
    /// zero. Both outcomes report `lossless = false`.
    function testPackLossySignificantDigitsBelowFloorAreShed(int256 m, uint256 d) external pure {
        m = bound(m, -1e16, 1e16);
        vm.assume(m % 10 != 0);
        d = bound(d, 1, 20);
        // Safe: d <= 20.
        //forge-lint: disable-next-line(unsafe-typecast)
        int256 exponent = INT32_MIN - int256(d);
        // Safe: d <= 20 so 10^d fits int256.
        //forge-lint: disable-next-line(unsafe-typecast)
        int256 expected = m / int256(10 ** d);

        (Float float, bool lossless) = LibDecimalFloat.packLossy(m, exponent);
        assertFalse(lossless, "lossless");
        if (expected == 0) {
            assertEq(Float.unwrap(float), Float.unwrap(LibDecimalFloat.FLOAT_ZERO), "zero");
        } else {
            (int256 c, int256 e) = LibDecimalFloat.unpack(float);
            assertEq(c, expected, "coeff");
            assertEq(e, INT32_MIN, "exp");
        }
    }

    /// `lossless` reports numeric equality, not whether the input already
    /// fitted: a coefficient beyond int224 that is an exact multiple of the
    /// power of ten it is divided by packs losslessly, in both signs.
    function testPackLossyExactMultipleBeyondInt224IsLossless() external pure {
        // int224.max is ~1.35e67, so 1e70 needs exactly three divisions.
        (Float float, bool lossless) = LibDecimalFloat.packLossy(1e70, 0);
        assertTrue(lossless, "lossless");
        (int256 c, int256 e) = LibDecimalFloat.unpack(float);
        assertEq(c, 1e67, "coeff");
        assertEq(e, 3, "exp");

        (float, lossless) = LibDecimalFloat.packLossy(-1e70, 0);
        assertTrue(lossless, "negative lossless");
        (c, e) = LibDecimalFloat.unpack(float);
        assertEq(c, -1e67, "negative coeff");
        assertEq(e, 3, "negative exp");

        // One non-zero digit inside the shed region and it is lossy again.
        (float, lossless) = LibDecimalFloat.packLossy(1e70 + 1, 0);
        assertFalse(lossless, "lossy");
        (c, e) = LibDecimalFloat.unpack(float);
        assertEq(c, 1e67, "lossy coeff");
        assertEq(e, 3, "lossy exp");
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

    /// Concrete: int224.min one below the floor sheds one digit, lossily, and
    /// lands at the floor. Negative-boundary twin of the int224.max case.
    function testPackLossyInt224MinOneBelowFloorShedsOneDigit() external pure {
        (Float float, bool lossless) = LibDecimalFloat.packLossy(INT224_MIN, INT32_MIN - 1);
        assertFalse(lossless, "lossless");
        (int256 c, int256 e) = LibDecimalFloat.unpack(float);
        assertEq(c, INT224_MIN / 10, "coeff");
        assertEq(e, INT32_MIN, "exp");
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

    /// The check from issue #271, verbatim. `-7e75` at exponent `-2147483723`
    /// is the maximised form of `-7e-2147483648`. The trailing zeros are what
    /// maximisation added, so shedding them costs nothing and brings the
    /// exponent back inside int32. Asserting the exact coefficient and
    /// exponent keeps this discriminating: a fix that clamps to zero, or that
    /// reaches a representable exponent by discarding significant digits,
    /// still fails it.
    function testPackLossyIssue271ShedsTrailingZerosToReachTheFloor() external pure {
        (Float f, bool lossless) = LibDecimalFloat.packLossy(-7e75, -2147483723);
        assertTrue(lossless, "lossless");
        (int256 c, int256 e) = LibDecimalFloat.unpack(f);
        assertEq(c, -7, "coefficient");
        assertEq(e, -2147483648, "exponent");
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
