// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

import {Test} from "forge-std-1.16.1/src/Test.sol";

contract LibDecimalFloatCanonicalizeTest is Test {
    using LibDecimalFloat for Float;

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
}
