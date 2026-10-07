// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibTestExactDecimal, U512} from "test/lib/LibTestExactDecimal.sol";

/// The single word helpers the error bounds use, against the 512 bit ones.
contract LibTestExactDecimalTest is Test {
    function testCmpWordsIsCmpScaled(uint256 x, int256 ex, uint256 y, int256 ey) external pure {
        ex = bound(ex, -200, 200);
        ey = bound(ey, -200, 200);
        assertEq(
            LibTestExactDecimal.cmpWords(x, ex, y, ey),
            LibTestExactDecimal.cmpScaled(LibTestExactDecimal.u512(x), ex, LibTestExactDecimal.u512(y), ey)
        );
    }

    /// Equal leading digits at different exponents, the case that aligns.
    function testCmpWordsAligned(uint256 x, uint256 shift, int256 delta) external pure {
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
        assertEq(LibTestExactDecimal.cmpWords(x, ex, y, 0), expected);
        assertEq(LibTestExactDecimal.cmpWords(y, 0, x, ex), -expected);
    }

    function testCmpPartsSigned(int256 a, int256 ea, int256 b, int256 eb) external pure {
        ea = bound(ea, -100, 100);
        eb = bound(eb, -100, 100);
        a = bound(a, type(int256).min + 1, type(int256).max);
        b = bound(b, type(int256).min + 1, type(int256).max);
        int256 expected;
        if (a < 0 && b < 0) {
            expected = LibTestExactDecimal.cmpWords(LibTestExactDecimal.abs(b), eb, LibTestExactDecimal.abs(a), ea);
        } else if (a >= 0 && b >= 0) {
            expected = LibTestExactDecimal.cmpWords(LibTestExactDecimal.abs(a), ea, LibTestExactDecimal.abs(b), eb);
        } else {
            expected = a < b ? int256(-1) : int256(1);
        }
        assertEq(LibTestExactDecimal.cmpParts(a, ea, b, eb), expected);
        assertEq(
            LibTestExactDecimal.absLte(a, ea, b, eb),
            LibTestExactDecimal.cmpWords(LibTestExactDecimal.abs(a), ea, LibTestExactDecimal.abs(b), eb) <= 0
        );
    }

    /// q |b| 10^(e + eb) <= |a| 10^ea < (q + 1) |b| 10^(e + eb), with q
    /// between 1e74 and 1e76. An |a| past 75 digits first sheds up to a unit
    /// of its 75th digit, which is under 10 units of q.
    function testQuotientTruncates(int256 a, int256 ea, int256 b, int256 eb) external pure {
        a = bound(a, type(int256).min + 1, type(int256).max);
        b = bound(b, type(int256).min + 1, type(int256).max);
        vm.assume(a != 0 && b != 0);
        ea = bound(ea, -100, 100);
        eb = bound(eb, -100, 100);
        (int256 q, int256 e) = LibTestExactDecimal.quotient(a, ea, b, eb);
        assertEq(q < 0, (a < 0) != (b < 0), "sign");
        uint256 magnitude = LibTestExactDecimal.abs(q);
        assertTrue(magnitude > 1e74 && magnitude < 1e76, "digits");
        uint256 absB = LibTestExactDecimal.abs(b);
        U512 memory exact = LibTestExactDecimal.u512(LibTestExactDecimal.abs(a));
        uint256 slack = LibTestExactDecimal.abs(a) < 1e75 ? 1 : 11;
        assertTrue(
            LibTestExactDecimal.cmpScaled(LibTestExactDecimal.mul(magnitude, absB), e + eb, exact, ea) <= 0, "floor"
        );
        assertTrue(
            LibTestExactDecimal.cmpScaled(LibTestExactDecimal.mul(magnitude + slack, absB), e + eb, exact, ea) > 0,
            "below the next"
        );
    }

    function testQuotientZero(int256 b, int256 ea, int256 eb) external pure {
        vm.assume(b != 0 && b != type(int256).min);
        (int256 q, int256 e) = LibTestExactDecimal.quotient(0, ea, b, eb);
        assertEq(q, 0);
        assertEq(e, 0);
    }

    /// Exact on the fast path, and agreeing with `subParts` off it.
    function testMinusOne(int256 c, int256 e) external pure {
        c = bound(c, type(int224).min, type(int224).max);
        e = bound(e, -90, 10);
        (int256 r, int256 re) = LibTestExactDecimal.minusOne(c, e);
        (int256 s, int256 se) = LibTestExactDecimal.subParts(c, e, 1, 0);
        assertTrue(LibTestExactDecimal.eq(r, re, s, se));
        if (e < 0 && e >= -67) {
            // forge-lint: disable-next-line(unsafe-typecast)
            assertEq(r, c - int256(10 ** uint256(-e)));
            assertEq(re, e);
        }
    }

    function testMinusOneOfOne() external pure {
        (int256 r,) = LibTestExactDecimal.minusOne(1e75, -75);
        assertEq(r, 0);
        (r,) = LibTestExactDecimal.minusOne(1e75 + 3, -75);
        assertEq(r, 3);
        (r,) = LibTestExactDecimal.minusOne(1e75 - 3, -75);
        assertEq(r, -3);
    }

    /// |r| 10^t <= |c| 10^e < (|r| + 1) 10^t, with the sign of c.
    function testAtExponentTruncates(int256 c, int256 e, int256 t) external pure {
        c = bound(c, type(int224).min, type(int224).max);
        e = bound(e, -100, 100);
        t = bound(t, e - 9, e + 100);
        int256 r = LibTestExactDecimal.atExponent(c, e, t);
        assertTrue(c < 0 ? r <= 0 : r >= 0, "sign");
        uint256 magnitude = LibTestExactDecimal.abs(r);
        U512 memory exact = LibTestExactDecimal.u512(LibTestExactDecimal.abs(c));
        assertTrue(LibTestExactDecimal.cmpScaled(LibTestExactDecimal.u512(magnitude), t, exact, e) <= 0, "floor");
        assertTrue(LibTestExactDecimal.cmpScaled(LibTestExactDecimal.u512(magnitude + 1), t, exact, e) > 0, "next");
    }
}
