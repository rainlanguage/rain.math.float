// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibExactFloat, U512} from "test/lib/LibExactFloat.sol";

/// The helpers the error bounds use, against plain 512 bit alignment.
contract LibExactFloatTest is Test {
    function cmpWords(uint256 x, int256 ex, uint256 y, int256 ey) private pure returns (int256) {
        return LibExactFloat.cmpScaled(LibExactFloat.u512(x), ex, LibExactFloat.u512(y), ey);
    }

    /// Single words aligned at the lower exponent, which fits 512 bits for a
    /// gap of at most 77 digits; past that the higher exponent's nonzero word
    /// is at least 10^78 units of the lower's, above any word.
    function testCmpScaledWords(uint256 x, int256 ex, uint256 y, int256 ey) external pure {
        ex = bound(ex, -200, 200);
        ey = bound(ey, -200, 200);
        int256 expected;
        if (x == 0 || y == 0) {
            expected = x < y ? int256(-1) : x > y ? int256(1) : int256(0);
        } else if (ex - ey >= 78) {
            expected = 1;
        } else if (ey - ex >= 78) {
            expected = -1;
        } else {
            U512 memory a = LibExactFloat.u512(x);
            U512 memory b = LibExactFloat.u512(y);
            if (ex > ey) {
                // forge-lint: disable-next-line(unsafe-typecast)
                a = LibExactFloat.mulPow10(a, uint256(ex - ey));
            } else {
                // forge-lint: disable-next-line(unsafe-typecast)
                b = LibExactFloat.mulPow10(b, uint256(ey - ex));
            }
            expected = LibExactFloat.cmp(a, b);
        }
        assertEq(LibExactFloat.cmpScaled(LibExactFloat.u512(x), ex, LibExactFloat.u512(y), ey), expected);
    }

    /// Equal leading digits at different exponents, the case that aligns.
    function testCmpScaledAligned(uint256 x, uint256 shift, int256 delta) external pure {
        shift = bound(shift, 1, 76);
        x = bound(x, 1, type(uint256).max / 10 ** shift);
        delta = bound(delta, -1, 1);
        uint256 y = x * 10 ** shift;
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 ex = int256(shift);
        int256 expected = delta;
        if (delta < 0) {
            y -= 1;
            expected = 1;
        } else if (delta > 0) {
            y += 1;
            expected = -1;
        }
        assertEq(cmpWords(x, ex, y, 0), expected);
        assertEq(cmpWords(y, 0, x, ex), -expected);
    }

    function testCmpPartsSigned(int256 a, int256 ea, int256 b, int256 eb) external pure {
        ea = bound(ea, -100, 100);
        eb = bound(eb, -100, 100);
        a = bound(a, type(int256).min + 1, type(int256).max);
        b = bound(b, type(int256).min + 1, type(int256).max);
        int256 expected;
        if (a < 0 && b < 0) {
            expected = cmpWords(LibExactFloat.abs(b), eb, LibExactFloat.abs(a), ea);
        } else if (a >= 0 && b >= 0) {
            expected = cmpWords(LibExactFloat.abs(a), ea, LibExactFloat.abs(b), eb);
        } else {
            expected = a < b ? int256(-1) : int256(1);
        }
        assertEq(LibExactFloat.cmpParts(a, ea, b, eb), expected);
    }

    /// q |b| 10^(e + eb) <= |a| 10^ea < (q + 1) |b| 10^(e + eb), with q in
    /// [1e74, 1e76) and the sign of a / b, or q = e = 0 for a = 0.
    function checkQuotient(int256 a, int256 ea, int256 b, int256 eb) internal pure {
        (int256 q, int256 e) = LibExactFloat.quotient(a, ea, b, eb);
        if (a == 0) {
            assertEq(q, 0, "zero");
            assertEq(e, 0, "zero exponent");
            return;
        }
        assertEq(q < 0, (a < 0) != (b < 0), "sign");
        uint256 magnitude = LibExactFloat.abs(q);
        assertTrue(magnitude >= 1e74 && magnitude < 1e76, "digits");
        uint256 absB = LibExactFloat.abs(b);
        U512 memory exact = LibExactFloat.u512(LibExactFloat.abs(a));
        assertTrue(LibExactFloat.cmpScaled(LibExactFloat.mul(magnitude, absB), e + eb, exact, ea) <= 0, "floor");
        assertTrue(
            LibExactFloat.cmpScaled(LibExactFloat.mul(magnitude + 1, absB), e + eb, exact, ea) > 0, "below the next"
        );
    }

    function testQuotientTruncates(int256 a, int256 ea, int256 b, int256 eb) external pure {
        vm.assume(b != 0);
        ea = bound(ea, type(int32).min, type(int32).max);
        eb = bound(eb, type(int32).min, type(int32).max);
        checkQuotient(a, ea, b, eb);
    }

    /// The ends of the range and the digit counts that pick each branch: a
    /// ratio just above 1e74 truncates to 1e74, a 77 digit a over a 1 digit b
    /// scales down, and a 1 digit a over a 77 digit b scales up past 1e77.
    function testQuotientEdges() external pure {
        (int256 q, int256 e) = LibExactFloat.quotient(1e75, 0, 1e76 - 1, 0);
        assertEq(q, 1e74);
        assertEq(e, -75);
        (q, e) = LibExactFloat.quotient(1, 0, 1, 0);
        assertEq(q, 1e75);
        assertEq(e, -75);
        (q, e) = LibExactFloat.quotient(9, 0, 1, 0);
        assertEq(q, 9e75);
        (q, e) = LibExactFloat.quotient(1, 0, 9, 0);
        assertEq(q, 111111111111111111111111111111111111111111111111111111111111111111111111111);
        assertEq(e, -75);
        checkQuotient(-7, 5, type(int256).min, -5);
        checkQuotient(type(int256).max, 0, 7, 3);
    }

    /// Each in a fresh call frame, so the grid's U512 allocations do not
    /// accumulate in one memory.
    function checkQuotientExternal(int256 a, int256 ea, int256 b, int256 eb) external pure {
        checkQuotient(a, ea, b, eb);
    }

    /// The digit-count extremes of both operands, both signs, at the Float
    /// exponent extremes.
    function testQuotientExtremes() external view {
        int256[14] memory c = [
            type(int256).max,
            type(int256).min,
            int256(type(int224).max),
            int256(type(int224).min),
            int256(1),
            int256(-1),
            int256(9),
            int256(-9),
            int256(10),
            int256(1e67),
            int256(1e67 - 1),
            int256(1e75),
            int256(1e76 - 1),
            int256(0)
        ];
        int256[3] memory ea = [int256(0), type(int32).max, type(int32).min];
        int256[3] memory eb = [int256(0), type(int32).min, type(int32).max];
        for (uint256 i = 0; i < c.length; i++) {
            for (uint256 j = 0; j < c.length - 1; j++) {
                for (uint256 k = 0; k < ea.length; k++) {
                    this.checkQuotientExternal(c[i], ea[k], c[j], eb[k]);
                }
            }
        }
    }

    function testQuotientZero(int256 b, int256 ea, int256 eb) external pure {
        vm.assume(b != 0 && b != type(int256).min);
        (int256 q, int256 e) = LibExactFloat.quotient(0, ea, b, eb);
        assertEq(q, 0);
        assertEq(e, 0);
    }

    /// The error measures subtract 1 from parts under 1e76 at exponents in
    /// [-76, -1] with `addPartsWide`, which is exact there: 1 and c are both
    /// whole units of the larger operand's int256 unit.
    function testAddPartsWideMinusOneExact(int256 c, int256 e) external pure {
        c = bound(c, -1e76 + 1, 1e76 - 1);
        e = bound(e, -76, -1);
        (bool overflowed, int256 r, int256 re) = LibExactFloat.addPartsWide(c, e, -1, 0);
        assertFalse(overflowed);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertTrue(LibExactFloat.eq(r, re, c - int256(10 ** uint256(-e)), e));
    }

    function testAddPartsWideMinusOneOfOne() external pure {
        (, int256 r,) = LibExactFloat.addPartsWide(1e75, -75, -1, 0);
        assertEq(r, 0);
        (, int256 s, int256 se) = LibExactFloat.addPartsWide(1e75 + 3, -75, -1, 0);
        assertTrue(LibExactFloat.eq(s, se, 3, -75));
        (, s, se) = LibExactFloat.addPartsWide(1e75 - 3, -75, -1, 0);
        assertTrue(LibExactFloat.eq(s, se, -3, -75));
    }

    /// |r| 10^t <= |c| 10^e < (|r| + 1) 10^t, with the sign of c.
    function testAtExponentTruncates(int256 c, int256 e, int256 t) external pure {
        c = bound(c, type(int224).min, type(int224).max);
        e = bound(e, -100, 100);
        t = bound(t, e - 9, e + 100);
        int256 r = LibExactFloat.atExponent(c, e, t);
        assertTrue(c < 0 ? r <= 0 : r >= 0, "sign");
        uint256 magnitude = LibExactFloat.abs(r);
        U512 memory exact = LibExactFloat.u512(LibExactFloat.abs(c));
        assertTrue(LibExactFloat.cmpScaled(LibExactFloat.u512(magnitude), t, exact, e) <= 0, "floor");
        assertTrue(LibExactFloat.cmpScaled(LibExactFloat.u512(magnitude + 1), t, exact, e) > 0, "next");
    }
}
