// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

contract LibDecimalFloatIsOddTest is Test {
    using LibDecimalFloat for Float;

    function isOdd(int256 signedCoefficient, int256 exponent) internal pure returns (bool) {
        return LibDecimalFloat.packLossless(signedCoefficient, exponent).isOdd();
    }

    function testIsOddConcrete() external pure {
        assertTrue(isOdd(1, 0));
        assertTrue(isOdd(3, 0));
        assertTrue(isOdd(-3, 0));
        assertTrue(isOdd(12345, 0));
        // Whole numbers written with a negative exponent.
        assertTrue(isOdd(30, -1));
        assertTrue(isOdd(-7000, -3));
        assertTrue(isOdd(type(int224).max, 0));
        assertTrue(isOdd(type(int224).min + 1, 0));

        assertFalse(isOdd(0, 0));
        assertFalse(isOdd(0, -5));
        assertFalse(isOdd(2, 0));
        assertFalse(isOdd(-4, 0));
        assertFalse(isOdd(type(int224).min, 0));
        // Positive exponents are multiples of ten.
        assertFalse(isOdd(1, 1));
        assertFalse(isOdd(3, type(int32).max));
        // Not whole.
        assertFalse(isOdd(15, -1));
        assertFalse(isOdd(-35, -1));
        assertFalse(isOdd(1, -1));
        assertFalse(isOdd(1, -67));
        assertFalse(isOdd(type(int224).max, -67));
        assertFalse(isOdd(type(int224).max, type(int32).min));
    }

    /// The most negative exponent that can still hold a whole number.
    function testIsOddAtTheDigitBoundary() external pure {
        // 3e66 has 67 digits; at exponent -66 it is exactly 3.
        assertTrue(isOdd(3e66, -66));
        assertFalse(isOdd(4e66, -66));
        // int224 tops out near 1.35e67, so at exponent -67 the only whole
        // values are 0 and ±1.
        assertTrue(isOdd(1e67, -67));
        assertTrue(isOdd(-1e67, -67));
        assertFalse(isOdd(1e67 + 1, -67));
    }

    /// Any whole number n, written as n * 10^k at exponent -k, has n's parity.
    function testIsOddWholeFuzz(int64 n, uint8 k) external pure {
        k = uint8(bound(k, 0, 48));
        int256 scaled = int256(n) * int256(10 ** uint256(k));
        assertEq(isOdd(scaled, -int256(uint256(k))), n % 2 != 0);
    }

    /// A value with a non-zero fractional part is never odd. int64 times
    /// 10^48 stays inside int224, so the input packs losslessly.
    function testIsOddFractionFuzz(int64 n, uint8 k) external pure {
        k = uint8(bound(k, 1, 48));
        int256 scaled = int256(n) * int256(10 ** uint256(k)) + (n < 0 ? int256(-1) : int256(1));
        assertFalse(isOdd(scaled, -int256(uint256(k))));
    }
}
