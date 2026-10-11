// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";

contract LibDecimalFloatCanonicalizeTest is Test {
    using LibDecimalFloat for Float;

    int224 constant INT224_MAX = type(int224).max;
    int224 constant INT224_MIN = type(int224).min;
    int32 constant INT32_MIN = type(int32).min;

    /// Exact numeric equality of two Floats.
    function exactEq(Float a, Float b) internal pure returns (bool) {
        (int256 ca, int256 ea) = a.unpack();
        (int256 cb, int256 eb) = b.unpack();
        return LibTestExactDecimal.eq(ca, ea, cb, eb);
    }

    /// The canonical form by the documented rule: the value's representation
    /// with the largest coefficient magnitude that fits int224 and an exponent
    /// at or above int32.min. Zero is `FLOAT_ZERO`. Built from the value's
    /// shortest representation, so every representation of a value gives the
    /// same answer.
    function canonicalOracle(Float float) internal pure returns (Float) {
        (int256 c, int256 e) = float.unpack();
        if (c == 0) {
            return LibDecimalFloat.FLOAT_ZERO;
        }
        while (c % 10 == 0) {
            c /= 10;
            e += 1;
        }
        int256 limit = c < 0 ? int256(INT224_MIN) : int256(INT224_MAX);
        while (e > INT32_MIN && (c < 0 ? c >= limit / 10 : c <= limit / 10)) {
            c *= 10;
            e -= 1;
        }
        return LibDecimalFloat.packLossless(c, e);
    }

    /// The largest s with c 10^s in int224 and e - s >= int32.min, for c
    /// nonzero.
    function maxShift(int256 c, int256 e) internal pure returns (uint256 s) {
        int256 limit = c < 0 ? int256(INT224_MIN) : int256(INT224_MAX);
        while (e > INT32_MIN && (c < 0 ? c >= limit / 10 : c <= limit / 10)) {
            c *= 10;
            e -= 1;
            s++;
        }
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
        assertTrue(exactEq(f, f.canonicalize()), "value preserved");
    }

    /// canonicalize is idempotent for a concrete value.
    function testCanonicalizeIdempotent() external pure {
        Float f = LibDecimalFloat.packLossless(42, 7);
        Float once = f.canonicalize();
        Float twice = once.canonicalize();
        assertEq(Float.unwrap(once), Float.unwrap(twice), "idempotent");
    }

    /// Fuzz: canonicalize preserves the numeric value for any valid Float, and
    /// is the documented representative.
    function testCanonicalizeValuePreservingFuzz(int224 signedCoefficient, int32 exponent) external pure {
        Float f = LibDecimalFloat.packLossless(signedCoefficient, exponent);
        Float canonical = f.canonicalize();
        assertTrue(exactEq(f, canonical), "value preserved");
        assertEq(Float.unwrap(canonical), Float.unwrap(canonicalOracle(f)), "documented representative");
    }

    /// Fuzz: canonicalize is idempotent for any valid Float.
    function testCanonicalizeIdempotentFuzz(int224 signedCoefficient, int32 exponent) external pure {
        Float f = LibDecimalFloat.packLossless(signedCoefficient, exponent);
        Float once = f.canonicalize();
        Float twice = once.canonicalize();
        assertEq(Float.unwrap(once), Float.unwrap(twice), "idempotent");
    }

    /// Fuzz: two Floats that are numerically equal (same coefficient shifted by
    /// a power of ten) are byte-equal after canonicalize. Every nonzero Float
    /// is the base, and every shift that leaves another Float of the same
    /// value: the shifted coefficient fits int224 and its exponent int32.
    function testCanonicalizeEqImpliesByteEqualFuzz(int224 signedCoefficient, int32 exponent, uint256 shift)
        external
        pure
    {
        // Avoid the degenerate all-zero case where the shift is irrelevant; it
        // is covered separately by testCanonicalizeZero.
        vm.assume(signedCoefficient != 0);

        checkEqImpliesByteEqual(signedCoefficient, exponent, bound(shift, 0, maxShift(signedCoefficient, exponent)));
    }

    /// Fuzz: the same at a base with room to shift, at least one digit short
    /// of int224 and above the exponent floor, by a shift of at least one, so
    /// the two representations differ.
    function testCanonicalizeEqImpliesByteEqualShiftedFuzz(
        int224 signedCoefficient,
        uint256 drop,
        int32 exponent,
        uint256 shift
    ) external pure {
        // Safe: 10^67 fits int224.
        //forge-lint: disable-next-line(unsafe-typecast)
        signedCoefficient /= int224(int256(10 ** bound(drop, 1, 67)));
        vm.assume(signedCoefficient != 0);
        // Safe: bounded within int32.
        //forge-lint: disable-next-line(unsafe-typecast)
        exponent = int32(bound(exponent, int256(INT32_MIN) + 1, type(int32).max));
        uint256 maxS = maxShift(signedCoefficient, exponent);
        assertGe(maxS, 1, "room to shift");
        checkEqImpliesByteEqual(signedCoefficient, exponent, bound(shift, 1, maxS));
    }

    /// `signedCoefficient × 10^exponent` and the same value with the
    /// coefficient shifted up `shift` digits canonicalize to the same bytes,
    /// the documented representative.
    function checkEqImpliesByteEqual(int224 signedCoefficient, int32 exponent, uint256 shift) internal pure {
        Float a = LibDecimalFloat.packLossless(signedCoefficient, exponent);
        // Shifted representation of the same value: multiply the coefficient by
        // 10^shift and lower the exponent by the same amount.
        // Safe: c 10^shift fits int224, so 10^shift is at most 10^67.
        //forge-lint: disable-next-line(unsafe-typecast)
        int256 shiftedCoefficient = int256(signedCoefficient) * int256(10 ** shift);
        //forge-lint: disable-next-line(unsafe-typecast)
        Float b = LibDecimalFloat.packLossless(shiftedCoefficient, int256(exponent) - int256(shift));

        // Same numeric value.
        assertTrue(exactEq(a, b), "same value precondition");

        // Byte-equal after canonicalize, and the documented representative.
        assertEq(
            Float.unwrap(a.canonicalize()), Float.unwrap(b.canonicalize()), "eq implies byte-equal after canonicalize"
        );
        assertEq(Float.unwrap(b.canonicalize()), Float.unwrap(canonicalOracle(a)), "documented representative");
    }

    /// Concrete no-collision at the int32.min exponent floor. Two tiny values
    /// pinned at the floor that differ only in their (already minimal)
    /// coefficient must NOT collapse to the same bytes. At the floor the loop
    /// cannot scale, so this directly exercises whether distinct floor-pinned
    /// coefficients survive distinct.
    function testCanonicalizeNoCollisionAtFloorConcrete() external pure {
        // 1e(int32.min) and 2e(int32.min): genuinely different numbers.
        Float a = LibDecimalFloat.packLossless(1, INT32_MIN);
        Float b = LibDecimalFloat.packLossless(2, INT32_MIN);
        assertTrue(!exactEq(a, b), "precondition: distinct values");
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
        if (!exactEq(a, b)) {
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
        if (!exactEq(a, b)) {
            assertTrue(
                Float.unwrap(a.canonicalize()) != Float.unwrap(b.canonicalize()),
                "distinct near-floor values must not collide"
            );
        }
    }

    /// Same value reached two different ways, both bottoming out at the floor.
    /// 10e(min) and 1e(min+1) are the same number; both must canonicalize to the
    /// identical bytes even though one starts already-scaled.
    function testCanonicalizeFloorCrossRepConcrete() external pure {
        Float a = LibDecimalFloat.packLossless(10, INT32_MIN);
        Float b = LibDecimalFloat.packLossless(1, int32(int256(INT32_MIN) + 1));
        assertTrue(exactEq(a, b), "precondition: same value");
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
    /// Every nonzero int224 base, in the band of 255 exponents above the floor,
    /// with every shift that keeps the scaled coefficient in int224 and its
    /// exponent at or above the floor. The band is where the floor caps the
    /// loop. `testCanonicalizeEqImpliesByteEqualFuzz` runs the same check at
    /// every exponent.
    function testCanonicalizeFloorCrossRepFuzz(int224 base, uint8 k, uint256 j) external pure {
        vm.assume(base != 0);
        // Safe: k <= 255, so the exponent stays within int32.
        //forge-lint: disable-next-line(unsafe-typecast)
        int32 expA = int32(int256(INT32_MIN) + int256(uint256(k)));
        checkFloorCrossRep(base, expA, bound(j, 0, maxShift(base, expA)));
    }

    /// The same at a base with room to shift, at least one digit short of
    /// int224 and at least one exponent above the floor, by a shift of at
    /// least one, so the two representations differ.
    function testCanonicalizeFloorCrossRepShiftedFuzz(int224 base, uint256 drop, uint8 k, uint256 j) external pure {
        // Safe: 10^67 fits int224.
        //forge-lint: disable-next-line(unsafe-typecast)
        base /= int224(int256(10 ** bound(drop, 1, 67)));
        vm.assume(base != 0);
        // Safe: 1 <= k <= 255, so the exponent stays within int32.
        //forge-lint: disable-next-line(unsafe-typecast)
        int32 expA = int32(int256(INT32_MIN) + int256(bound(k, 1, 255)));
        uint256 maxS = maxShift(base, expA);
        assertGe(maxS, 1, "room to shift");
        checkFloorCrossRep(base, expA, bound(j, 1, maxS));
    }

    function checkFloorCrossRep(int224 base, int32 expA, uint256 j) internal pure {
        // Safe: base 10^j fits int224, so 10^j is at most 10^67.
        //forge-lint: disable-next-line(unsafe-typecast)
        int256 scaled = int256(base) * int256(10 ** j);
        // Safe: j <= 67.
        //forge-lint: disable-next-line(unsafe-typecast)
        int256 expB = int256(expA) - int256(j);

        Float a = LibDecimalFloat.packLossless(base, expA);
        Float b = LibDecimalFloat.packLossless(scaled, expB);
        assertTrue(exactEq(a, b), "precondition: same value");
        assertEq(
            Float.unwrap(a.canonicalize()), Float.unwrap(b.canonicalize()), "cross-rep at floor must be byte-equal"
        );
        assertEq(Float.unwrap(a.canonicalize()), Float.unwrap(canonicalOracle(b)), "documented representative");
    }

    /// Value preservation at the floor where the coefficient is NOT maximised
    /// (the loop is capped by int32.min, leaving a small coefficient). 1e(min)
    /// cannot scale at all; the canonical form must still be `eq` to the input
    /// and idempotent.
    function testCanonicalizeFloorValuePreservedConcrete() external pure {
        Float f = LibDecimalFloat.packLossless(123, INT32_MIN);
        Float c = f.canonicalize();
        assertTrue(exactEq(f, c), "value preserved at floor");
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
            assertTrue(exactEq(f, c), "value preserved at int224 extreme");
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
        assertTrue(exactEq(f, c), "value preserved near floor");
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
        assertTrue(exactEq(f, c), "value preserved near int224 edge");
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
        bool numericallyEqual = exactEq(a, b);
        bool byteEqual = Float.unwrap(a.canonicalize()) == Float.unwrap(b.canonicalize());
        assertEq(numericallyEqual, byteEqual, "eq iff byte-equal after canonicalize");
    }
}
