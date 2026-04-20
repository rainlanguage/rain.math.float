// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Test} from "forge-std/Test.sol";
import {LibDecimalFloatSlow} from "test/lib/LibDecimalFloatSlow.sol";

contract LibDecimalFloatImplementationEqTest is Test {
    function testEqGasDifferentSigns() external pure {
        LibDecimalFloatImplementation.eq(1, 0, -1, 0);
    }

    function testEqGasAZero() external pure {
        LibDecimalFloatImplementation.eq(0, 0, 1, 0);
    }

    function testEqGasBZero() external pure {
        LibDecimalFloatImplementation.eq(1, 0, 0, 0);
    }

    function testEqGasBothZero() external pure {
        LibDecimalFloatImplementation.eq(0, 0, 0, 0);
    }

    function testEqGasExponentDiffOverflow() external pure {
        LibDecimalFloatImplementation.eq(1, type(int256).max, 1, type(int256).min);
    }

    /// if xeX == yeY, then x / y == 10^(X - Y) || y / x == 10^(Y - X)
    function testEqXEqY(int256 x, int256 exponentX, int256 y, int256 exponentY) external pure {
        bool eq = LibDecimalFloatImplementation.eq(x, exponentX, y, exponentY);

        if (eq) {
            if (x == y) {
                assertTrue(exponentX == exponentY || x == 0);
            } else if (y > x) {
                assertTrue(exponentY < exponentX, "y > x but exponentY >= exponentX");
                assertTrue(exponentX - exponentY < 77, "y > x but exponentX - exponentY >= 77");
                // we assert that exponentY < exponentX and the diff is < 77.
                // forge-lint: disable-next-line(unsafe-typecast)
                assertEq(x / y, int256(10 ** uint256(exponentX - exponentY)), "y > x but x / y != 10^(X - Y)");
                assertEq(x % y, 0, "y > x but x % y != 0");
            } else {
                assertTrue(exponentX < exponentY, "x < y but exponentX >= exponentY");
                assertTrue(exponentY - exponentX < 77, "x < y but exponentY - exponentX >= 77");
                // x < y and they are eq so exponentY - exponentX will always be
                // positive.
                // forge-lint: disable-next-line(unsafe-typecast)
                assertEq(y / x, int256(10 ** uint256(exponentY - exponentX)), "x < y but y / x != 10^(Y - X)");
                assertEq(y % x, 0, "x < y but y % x != 0");
            }
        } else {
            if (x == y) {
                assertTrue(exponentX != exponentY);
            }
        }
    }

    /// xeX != yeY if x != y (assuming maximized representation)
    function testEqXNotY(int256 x, int256 exponentX, int256 y, int256 exponentY) external pure {
        (x, exponentX,) = LibDecimalFloatImplementation.maximize(x, exponentX);
        (y, exponentY,) = LibDecimalFloatImplementation.maximize(y, exponentY);
        vm.assume(x != y);
        bool eq = LibDecimalFloatImplementation.eq(x, exponentX, y, exponentY);
        assertTrue(!eq);
    }

    /// xeX != xeY if X != Y && x != 0
    function testEqXEAnyVsXEAny(int256 x, int256 exponentX, int256 exponentY) external pure {
        vm.assume(x != 0);
        bool eq = LibDecimalFloatImplementation.eq(x, exponentX, x, exponentY);

        assertEq(eq, exponentX == exponentY);

        // Reverse the order.
        eq = LibDecimalFloatImplementation.eq(x, exponentY, x, exponentX);
        assertEq(eq, exponentX == exponentY);
    }

    /// xeX == xeY if x == 0
    function testEqZero(int256 exponentX, int256 exponentY) external pure {
        bool eq = LibDecimalFloatImplementation.eq(0, exponentX, 0, exponentY);
        assertTrue(eq);
    }

    function testEqNotReverts(int256 x, int256 exponentX, int256 y, int256 exponentY) external pure {
        LibDecimalFloatImplementation.eq(x, exponentX, y, exponentY);
    }

    /// x == x
    function testEqX(int256 x) external pure {
        bool eq = LibDecimalFloatImplementation.eq(x, 0, x, 0);
        assertTrue(eq);
    }

    /// xeX == xeX
    function testEqOneEAny(int256 x, int256 exponent) external pure {
        bool eq = LibDecimalFloatImplementation.eq(x, exponent, x, exponent);
        assertTrue(eq);
    }

    function testEqReference(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
    {
        bool actual = LibDecimalFloatImplementation.eq(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        bool expected = LibDecimalFloatSlow.eqSlow(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        assertEq(actual, expected);
    }

    /// Equal values with exponent difference exactly 76 (the last diff that
    /// does NOT take the overflow-guard branch in `compareRescale`). Construct
    /// the pair as (1, 76) and (10^76, 0): both fit int256 (max ≈ 5.79e76),
    /// both represent 10^76.
    function testEqDiff76Boundary() external pure {
        int256 cSmall = 1;
        int256 eSmall = 76;
        int256 cBig = int256(1e76);
        int256 eBig = 0;
        assertTrue(LibDecimalFloatImplementation.eq(cSmall, eSmall, cBig, eBig));
        assertTrue(LibDecimalFloatImplementation.eq(cBig, eBig, cSmall, eSmall));
    }

    /// Equal-value pairs with exponent difference > 76 are not constructible
    /// at the int256 interface. The overflow-guard branch in `compareRescale`
    /// (`sgt(exponentDiff, 76)`) only fires when the values are already
    /// unequal to at least 10^77x apart. Any attempted equal-value pair with
    /// diff ≥ 77 requires a coefficient ≥ 10^77, which exceeds int256 max.
    /// This test exercises diff = 77 with unequal values and asserts eq is
    /// correctly false — the guard's truncation is sound here.
    function testEqDiff77OverflowGuardUnequal() external pure {
        int256 cA = 1;
        int256 eA = 77;
        int256 cB = 1;
        int256 eB = 0;
        // 10^77 != 10^0. Diff = 77 takes the overflow-guard path.
        assertFalse(LibDecimalFloatImplementation.eq(cA, eA, cB, eB));
        assertFalse(LibDecimalFloatImplementation.eq(cB, eB, cA, eA));
    }

    /// Fuzz: for any `(base, shift)` where `base × 10^shift` fits int256,
    /// `(base, 0)` and `(base × 10^shift, -shift)` represent the same value
    /// and must compare equal. Covers the range of constructible equal-value
    /// pairs.
    function testEqSameValueDifferentRepresentations(int256 base, uint8 shift) external pure {
        vm.assume(base != 0);
        vm.assume(base != type(int256).min);
        int256 absBase = base < 0 ? -base : base;

        // Largest `shift` such that `absBase * 10^shift` still fits int256.
        uint256 maxShift = 0;
        int256 scale = 1;
        while (scale <= type(int256).max / 10 / absBase) {
            scale *= 10;
            maxShift++;
        }
        if (maxShift == 0) {
            return;
        }
        uint256 s = bound(shift, 1, maxShift);
        int256 scaled = base * int256(10 ** s);

        // `s` is bounded to `maxShift` which is at most ~76 (the loop above
        // stops when `10^s * absBase` would exceed int256 max). The cast to
        // int256 is safe.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 negS = -int256(s);
        bool result = LibDecimalFloatImplementation.eq(base, 0, scaled, negS);
        assertTrue(result, "eq returned false for equivalent representations");
        bool reversed = LibDecimalFloatImplementation.eq(scaled, negS, base, 0);
        assertTrue(reversed, "eq returned false for equivalent representations (reversed)");
    }
}
