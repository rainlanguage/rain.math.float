// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

import {Test} from "forge-std-1.16.1/src/Test.sol";

contract LibDecimalFloatCanonicalizeTest is Test {
    using LibDecimalFloat for Float;

    int224 constant INT224_MAX = type(int224).max;
    int224 constant INT224_MIN = type(int224).min;
    int32 constant INT32_MIN = type(int32).min;

    function canonicalizeExternal(Float float) external pure returns (Float) {
        return float.canonicalize();
    }

    /// Zero at any exponent canonicalizes to FLOAT_ZERO.
    function testCanonicalizeZero(int32 exponent) external pure {
        Float zero = LibDecimalFloat.packLossless(0, exponent);
        Float canonical = zero.canonicalize();
        assertEq(Float.unwrap(canonical), Float.unwrap(LibDecimalFloat.FLOAT_ZERO), "zero canonicalizes to FLOAT_ZERO");
    }

    /// Several different byte representations of the same positive value all
    /// canonicalize to the same bytes32.
    function testCanonicalizeEqualValuesByteEqual() external pure {
        bytes32 expected = Float.unwrap(LibDecimalFloat.packLossless(5, 0).canonicalize());
        assertEq(Float.unwrap(LibDecimalFloat.packLossless(50, -1).canonicalize()), expected, "50e-1");
        assertEq(Float.unwrap(LibDecimalFloat.packLossless(5000, -3).canonicalize()), expected, "5000e-3");
        assertEq(Float.unwrap(LibDecimalFloat.packLossless(5e10, -10).canonicalize()), expected, "5e10 e-10");
    }

    /// Same as above for a negative value.
    function testCanonicalizeNegativeEqualValuesByteEqual() external pure {
        bytes32 expected = Float.unwrap(LibDecimalFloat.packLossless(-5, 0).canonicalize());
        assertEq(Float.unwrap(LibDecimalFloat.packLossless(-50, -1).canonicalize()), expected, "-50e-1");
        assertEq(Float.unwrap(LibDecimalFloat.packLossless(-5000, -3).canonicalize()), expected, "-5000e-3");
        assertEq(Float.unwrap(LibDecimalFloat.packLossless(-5e10, -10).canonicalize()), expected, "-5e10 e-10");
    }

    /// canonicalize preserves the numeric value.
    function testCanonicalizeValuePreserving() external pure {
        Float f = LibDecimalFloat.packLossless(1234567890, -3);
        assertTrue(f.eq(f.canonicalize()), "value preserved");
    }

    /// canonicalize is idempotent for a concrete value.
    function testCanonicalizeIdempotent() external pure {
        Float f = LibDecimalFloat.packLossless(42, 7);
        Float once = f.canonicalize();
        Float twice = once.canonicalize();
        assertEq(Float.unwrap(once), Float.unwrap(twice), "idempotent");
    }

    /// Fuzz: canonicalize preserves the numeric value for any valid Float.
    function testCanonicalizeValuePreservingFuzz(int224 signedCoefficient, int32 exponent) external pure {
        Float f = LibDecimalFloat.packLossless(signedCoefficient, exponent);
        Float canonical = f.canonicalize();
        assertTrue(f.eq(canonical), "value preserved");
    }

    /// Fuzz: canonicalize is idempotent for any valid Float.
    function testCanonicalizeIdempotentFuzz(int224 signedCoefficient, int32 exponent) external pure {
        Float f = LibDecimalFloat.packLossless(signedCoefficient, exponent);
        Float once = f.canonicalize();
        Float twice = once.canonicalize();
        assertEq(Float.unwrap(once), Float.unwrap(twice), "idempotent");
    }

    /// Fuzz: two Floats that are numerically equal (same coefficient shifted by
    /// a power of ten) are byte-equal after canonicalize.
    function testCanonicalizeEqImpliesByteEqualFuzz(int128 signedCoefficient, uint8 shift) external pure {
        // Avoid the degenerate all-zero case where the shift is irrelevant; it
        // is covered separately by testCanonicalizeZero.
        vm.assume(signedCoefficient != 0);

        // Base representation.
        Float a = LibDecimalFloat.packLossless(signedCoefficient, 0);

        // Shifted representation of the same value: multiply the coefficient by
        // 10^shift and lower the exponent by the same amount. int128 * 10^255
        // cannot overflow int256, so packLossless is safe here (it tolerates a
        // coefficient that does not fit int224 only via packLossy, but for
        // shift large enough to exceed int224 we would need packLossy; keep the
        // shift bounded so the shifted coefficient still fits int224).
        uint256 boundedShift = shift % 19;
        int256 shiftedCoefficient = int256(signedCoefficient) * int256(10 ** boundedShift);
        Float b = LibDecimalFloat.packLossless(shiftedCoefficient, -int256(boundedShift));

        // Same numeric value.
        assertTrue(a.eq(b), "same value precondition");

        // Byte-equal after canonicalize.
        assertEq(
            Float.unwrap(a.canonicalize()), Float.unwrap(b.canonicalize()), "eq implies byte-equal after canonicalize"
        );
    }

    // ---------------------------------------------------------------------
    // Adversarial coverage that deliberately leaves the int128/uint8 "easy
    // middle" the tests above stay inside. These target the int224 and int32
    // type boundaries and, crucially, assert the SAFETY property the tests
    // above never check: numerically DISTINCT Floats must canonicalize to
    // byte-UNEQUAL results (no collision). They also pin the exponent to the
    // int32.min floor where the scaling loop is capped before the coefficient
    // is maximised, and the int224.min/int224.max coefficient boundaries.
    // ---------------------------------------------------------------------

    // ---------------------------------------------------------------------
    // NO-COLLISION: numerically distinct -> byte-UNEQUAL after canonicalize.
    // ---------------------------------------------------------------------

    /// Concrete no-collision at the int32.min exponent floor. Two tiny values
    /// pinned at the floor that differ only in their (already minimal)
    /// coefficient must NOT collapse to the same bytes. At the floor the loop
    /// cannot scale, so this directly exercises whether distinct floor-pinned
    /// coefficients survive distinct.
    function testCanonicalizeNoCollisionAtFloorConcrete() external pure {
        // 1e(int32.min) and 2e(int32.min): genuinely different numbers.
        Float a = LibDecimalFloat.packLossless(1, INT32_MIN);
        Float b = LibDecimalFloat.packLossless(2, INT32_MIN);
        assertTrue(!a.eq(b), "precondition: distinct values");
        assertTrue(
            Float.unwrap(a.canonicalize()) != Float.unwrap(b.canonicalize()),
            "distinct floor-pinned values must not collide"
        );
    }

    /// Concrete no-collision where one value's loop is capped by the int224
    /// bound and a neighbouring distinct value's is too. Maximised positive vs.
    /// negative of nearly-equal magnitude must not collide.
    function testCanonicalizeNoCollisionInt224CapConcrete() external pure {
        Float a = LibDecimalFloat.packLossless(7, 0);
        Float b = LibDecimalFloat.packLossless(7, 1); // 70, distinct value
        Float c = LibDecimalFloat.packLossless(-7, 0); // distinct sign
        bytes32 ca = Float.unwrap(a.canonicalize());
        bytes32 cb = Float.unwrap(b.canonicalize());
        bytes32 cc = Float.unwrap(c.canonicalize());
        assertTrue(ca != cb, "7e0 vs 70e0 must not collide");
        assertTrue(ca != cc, "7 vs -7 must not collide");
        assertTrue(cb != cc, "70 vs -7 must not collide");
    }

    /// Fuzz no-collision across the FULL int224/int32 box. Build two Floats from
    /// raw boundary-capable inputs; if they are numerically distinct (`!eq`),
    /// their canonical forms must be byte-distinct. `eq` is the library's own
    /// numeric-equality oracle, so this is exactly the documented guarantee
    /// "two Floats are numerically equal iff their canonical forms are
    /// byte-equal" applied in the contrapositive.
    function testCanonicalizeNoCollisionFuzz(int224 coefficientA, int32 exponentA, int224 coefficientB, int32 exponentB)
        external
        pure
    {
        Float a = LibDecimalFloat.packLossless(coefficientA, exponentA);
        Float b = LibDecimalFloat.packLossless(coefficientB, exponentB);
        if (!a.eq(b)) {
            assertTrue(
                Float.unwrap(a.canonicalize()) != Float.unwrap(b.canonicalize()),
                "distinct values must canonicalize to distinct bytes"
            );
        }
    }

    /// Fuzz no-collision focused at the int32.min floor: both operands pinned to
    /// a narrow band just above the floor so the loop terminates at the floor
    /// for small coefficients, the regime the tests above never reach.
    function testCanonicalizeNoCollisionNearFloorFuzz(int224 coefficientA, int224 coefficientB, uint8 lift)
        external
        pure
    {
        // Exponent within [int32.min, int32.min + 255]: the floor band.
        int32 exponent = int32(int256(INT32_MIN) + int256(uint256(lift)));
        Float a = LibDecimalFloat.packLossless(coefficientA, exponent);
        Float b = LibDecimalFloat.packLossless(coefficientB, exponent);
        if (!a.eq(b)) {
            assertTrue(
                Float.unwrap(a.canonicalize()) != Float.unwrap(b.canonicalize()),
                "distinct near-floor values must not collide"
            );
        }
    }

    // ---------------------------------------------------------------------
    // EQ -> BYTE-EQUAL across representations, driven at the FLOOR and the
    // int224 cap (the (c) hunt: same value via different starting reps).
    // ---------------------------------------------------------------------

    /// Same value reached two different ways, both bottoming out at the floor.
    /// 10e(min) and 1e(min+1) are the same number; both must canonicalize to the
    /// identical bytes even though one starts already-scaled.
    function testCanonicalizeFloorCrossRepConcrete() external pure {
        Float a = LibDecimalFloat.packLossless(10, INT32_MIN);
        Float b = LibDecimalFloat.packLossless(1, int32(int256(INT32_MIN) + 1));
        assertTrue(a.eq(b), "precondition: same value");
        assertEq(
            Float.unwrap(a.canonicalize()),
            Float.unwrap(b.canonicalize()),
            "same value at floor -> identical canonical bytes"
        );
    }

    /// Fuzz: a value whose loop is capped by the floor, reached from two
    /// different starting representations, canonicalizes identically. Start with
    /// coefficient `base` at `int32.min + k`, and the pre-scaled `base*10^j` at
    /// `int32.min + k - j`; both encode the same value and both must hit the
    /// same floor-capped canonical form.
    function testCanonicalizeFloorCrossRepFuzz(int64 base, uint8 k, uint8 j) external pure {
        vm.assume(base != 0);
        // Keep both exponents in the floor band and >= int32.min.
        uint256 kk = uint256(k) % 30 + 1; // 1..30
        uint256 jj = uint256(j) % kk; // 0..kk-1 so exp stays >= floor
        int32 expA = int32(int256(INT32_MIN) + int256(kk));
        // base * 10^jj still fits int224 comfortably (int64 * 10^29 < int224).
        int256 scaled = int256(base) * int256(10 ** jj);
        int32 expB = int32(int256(INT32_MIN) + int256(kk) - int256(jj));

        Float a = LibDecimalFloat.packLossless(base, expA);
        Float b = LibDecimalFloat.packLossless(scaled, expB);
        assertTrue(a.eq(b), "precondition: same value");
        assertEq(
            Float.unwrap(a.canonicalize()), Float.unwrap(b.canonicalize()), "cross-rep at floor must be byte-equal"
        );
    }

    // ---------------------------------------------------------------------
    // VALUE PRESERVATION + IDEMPOTENCE at the int224/int32 boundaries the
    // tests above avoid.
    // ---------------------------------------------------------------------

    /// Value preservation at the floor where the coefficient is NOT maximised
    /// (the loop is capped by int32.min, leaving a small coefficient). 1e(min)
    /// cannot scale at all; the canonical form must still be `eq` to the input
    /// and idempotent.
    function testCanonicalizeFloorValuePreservedConcrete() external pure {
        Float f = LibDecimalFloat.packLossless(123, INT32_MIN);
        Float c = f.canonicalize();
        assertTrue(f.eq(c), "value preserved at floor");
        // At the floor with a tiny coefficient the loop cannot run, so the form
        // is already canonical: the input bytes must equal the canonical bytes.
        assertEq(Float.unwrap(c), Float.unwrap(f), "floor-pinned tiny coeff is already canonical");
        assertEq(Float.unwrap(c.canonicalize()), Float.unwrap(c), "idempotent at floor");
    }

    /// int224.max / int224.min coefficients: already at the magnitude ceiling so
    /// the loop cannot scale (×10 overflows int224). Value-preserving and
    /// idempotent, and the input is already its own canonical form.
    function testCanonicalizeInt224ExtremesConcrete() external pure {
        int224[2] memory extremes = [INT224_MAX, INT224_MIN];
        for (uint256 i = 0; i < extremes.length; i++) {
            Float f = LibDecimalFloat.packLossless(extremes[i], 3);
            Float c = f.canonicalize();
            assertTrue(f.eq(c), "value preserved at int224 extreme");
            assertEq(Float.unwrap(c), Float.unwrap(f), "int224 extreme already canonical");
            assertEq(Float.unwrap(c.canonicalize()), Float.unwrap(c), "idempotent at int224 extreme");
        }
    }

    /// Fuzz value-preservation + idempotence pinned to the int32.min floor band.
    /// This is the regime the uniform-int32-exponent fuzz above almost never
    /// samples.
    function testCanonicalizeFloorValuePreservedFuzz(int224 coefficient, uint16 lift) external pure {
        int32 exponent = int32(int256(INT32_MIN) + int256(uint256(lift)));
        Float f = LibDecimalFloat.packLossless(coefficient, exponent);
        Float c = f.canonicalize();
        assertTrue(f.eq(c), "value preserved near floor");
        assertEq(Float.unwrap(c.canonicalize()), Float.unwrap(c), "idempotent near floor");
    }

    /// Fuzz value-preservation + idempotence with coefficients pinned to the
    /// top/bottom of the int224 range (where the loop terminates immediately or
    /// after a single step), across arbitrary int32 exponents.
    function testCanonicalizeInt224EdgeValuePreservedFuzz(uint64 delta, bool negative, int32 exponent) external pure {
        // Coefficient within `delta` of an int224 extreme.
        int256 coefficient =
            negative ? int256(INT224_MIN) + int256(uint256(delta)) : int256(INT224_MAX) - int256(uint256(delta));
        Float f = LibDecimalFloat.packLossless(coefficient, exponent);
        Float c = f.canonicalize();
        assertTrue(f.eq(c), "value preserved near int224 edge");
        assertEq(Float.unwrap(c.canonicalize()), Float.unwrap(c), "idempotent near int224 edge");
    }

    /// Fuzz the documented end-to-end guarantee at full boundary width: build two
    /// Floats from raw int224/int32 inputs and assert `eq` <=> byte-equal after
    /// canonicalize (both directions in one test). The eq->byte-equal fuzz above
    /// only ever feeds equal values; this also feeds unequal ones.
    function testCanonicalizeEqIffByteEqualFuzz(
        int224 coefficientA,
        int32 exponentA,
        int224 coefficientB,
        int32 exponentB
    ) external pure {
        Float a = LibDecimalFloat.packLossless(coefficientA, exponentA);
        Float b = LibDecimalFloat.packLossless(coefficientB, exponentB);
        bool numericallyEqual = a.eq(b);
        bool byteEqual = Float.unwrap(a.canonicalize()) == Float.unwrap(b.canonicalize());
        assertEq(numericallyEqual, byteEqual, "eq iff byte-equal after canonicalize");
    }
}
