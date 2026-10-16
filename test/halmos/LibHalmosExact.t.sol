// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibHalmosExact, VM} from "./LibHalmosExact.sol";
import {LibExactFloat} from "../lib/LibExactFloat.sol";

/// The exact helpers the Halmos lemmas filter and compare with, against
/// references independent of them: digit counts by repeated division, values
/// through `LibExactFloat`'s 512 bit comparison, and each hint filter's
/// NatSpec claim at the boundaries it turns on.
contract LibHalmosExactTest is Test {
    /// floor(int256.max / 10).
    uint256 internal constant T10 = uint256(type(int256).max) / 10;

    /// The decimal digit count of x, zero for zero.
    function digitsOf(uint256 x) internal pure returns (uint256 n) {
        while (x > 0) {
            x /= 10;
            n++;
        }
    }

    /// x as an int256 of the sign asked for, for x at most 2^255.
    function signed(uint256 x, bool negative) internal pure returns (int256) {
        if (negative) {
            if (x == 2 ** 255) {
                return type(int256).min;
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            return -int256(x);
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return int256(x);
    }

    /// A coefficient of j + 1 digits: |c| in [10^j, 10^(j + 1)), cut to
    /// int256 at j = 76.
    function withDigits(uint256 seed, uint256 j, bool negative) internal pure returns (int256) {
        uint256 hi = j == 76 ? (negative ? 2 ** 255 : 2 ** 255 - 1) : 10 ** (j + 1) - 1;
        return signed(bound(seed, 10 ** j, hi), negative);
    }

    function testVmAddress() external pure {
        assertEq(address(VM), address(vm));
    }

    function testAbs(int256 x) external pure {
        assertEq(LibHalmosExact.abs(x), LibExactFloat.abs(x));
    }

    function testAbsExtremes() external pure {
        assertEq(LibHalmosExact.abs(type(int256).min), 2 ** 255);
        assertEq(LibHalmosExact.abs(type(int256).max), uint256(type(int256).max));
        assertEq(LibHalmosExact.abs(-1), 1);
        assertEq(LibHalmosExact.abs(0), 0);
        assertEq(LibHalmosExact.abs(1), 1);
    }

    /// `hasDigits(c, j)` iff c has j + 1 digits, or is zero at j = 77.
    function testHasDigits(int256 c, uint8 jSeed) external pure {
        uint256 j = bound(uint256(jSeed), 0, 77);
        bool expected = c == 0 ? j == 77 : digitsOf(LibExactFloat.abs(c)) == j + 1;
        assertEq(LibHalmosExact.hasDigits(c, j), expected);
    }

    /// Every int256 has exactly one j in [0, 77].
    function testHasDigitsExactlyOne(int256 c) external pure {
        uint256 count = 0;
        for (uint256 j = 0; j <= 77; j++) {
            if (LibHalmosExact.hasDigits(c, j)) {
                count++;
            }
        }
        assertEq(count, 1);
    }

    /// Each power of ten opens a digit count and the number before it closes
    /// the one below, for either sign.
    function testHasDigitsAtPowersOfTen() external pure {
        for (uint256 k = 0; k <= 76; k++) {
            int256 p = signed(10 ** k, false);
            assertTrue(LibHalmosExact.hasDigits(p, k));
            assertTrue(LibHalmosExact.hasDigits(-p, k));
            assertFalse(LibHalmosExact.hasDigits(p, k + 1));
            assertFalse(LibHalmosExact.hasDigits(-p, k + 1));
            if (k > 0) {
                assertTrue(LibHalmosExact.hasDigits(p - 1, k - 1));
                assertTrue(LibHalmosExact.hasDigits(1 - p, k - 1));
                assertFalse(LibHalmosExact.hasDigits(p - 1, k));
                assertFalse(LibHalmosExact.hasDigits(p, k - 1));
            }
        }
        assertTrue(LibHalmosExact.hasDigits(type(int256).min, 76));
        assertTrue(LibHalmosExact.hasDigits(type(int256).max, 76));
        assertFalse(LibHalmosExact.hasDigits(type(int256).min, 75));
        assertFalse(LibHalmosExact.hasDigits(type(int256).min, 77));
        assertTrue(LibHalmosExact.hasDigits(0, 77));
        assertFalse(LibHalmosExact.hasDigits(0, 76));
        assertFalse(LibHalmosExact.hasDigits(0, 0));
        assertFalse(LibHalmosExact.hasDigits(1, 77));
    }

    /// True for every x and positive d.
    function testDivHint(int256 x, int256 d) external pure {
        d = bound(d, 1, type(int256).max);
        assertTrue(LibHalmosExact.divHint(x, d));
    }

    /// Either side of |x| = d, where the quotient leaves zero.
    function testDivHintAtDivisor(int256 d) external pure {
        d = bound(d, 1, type(int256).max);
        assertTrue(LibHalmosExact.divHint(d, d));
        assertTrue(LibHalmosExact.divHint(-d, d));
        assertTrue(LibHalmosExact.divHint(d - 1, d));
        assertTrue(LibHalmosExact.divHint(1 - d, d));
        if (d < type(int256).max) {
            assertTrue(LibHalmosExact.divHint(d + 1, d));
            assertTrue(LibHalmosExact.divHint(-d - 1, d));
        }
        assertTrue(LibHalmosExact.divHint(0, d));
        assertTrue(LibHalmosExact.divHint(type(int256).min, d));
        assertTrue(LibHalmosExact.divHint(type(int256).max, d));
    }

    /// Under its precondition (c of j + 1 digits, s = 0 or s + j < 76) for
    /// every t at most 76.
    function testShiftHint(uint256 seed, bool negative, uint8 jSeed, uint8 sSeed, uint8 tSeed) external pure {
        uint256 j = bound(uint256(jSeed), 0, 76);
        uint256 s = j < 75 ? bound(uint256(sSeed), 0, 75 - j) : 0;
        uint256 t = bound(uint256(tSeed), 0, 76);
        assertTrue(LibHalmosExact.shiftHint(withDigits(seed, j, negative), s, j, t));
    }

    /// At t = s + j the shifted value has reached 10^t; at t one more it has
    /// not, at t one less it has.
    function testShiftHintAtThreshold(uint256 seed, bool negative, uint8 jSeed, uint8 sSeed) external pure {
        uint256 j = bound(uint256(jSeed), 0, 76);
        uint256 s = j < 75 ? bound(uint256(sSeed), 0, 75 - j) : 0;
        int256 c = withDigits(seed, j, negative);
        assertTrue(LibHalmosExact.shiftHint(c, s, j, s + j));
        if (s + j < 76) {
            assertTrue(LibHalmosExact.shiftHint(c, s, j, s + j + 1));
        }
        if (s + j > 0) {
            assertTrue(LibHalmosExact.shiftHint(c, s, j, s + j - 1));
        }
    }

    /// Under its precondition for every c and shift.
    function testTimesTenHint(uint256 seed, bool negative, uint8 jSeed, uint8 sSeed) external pure {
        uint256 j = bound(uint256(jSeed), 0, 76);
        uint256 s = j < 75 ? bound(uint256(sSeed), 0, 75 - j) : 0;
        assertTrue(LibHalmosExact.timesTenHint(withDigits(seed, j, negative), s));
    }

    /// Either side of |c| = floor(T10 / 10^s), where c 10^s last fits
    /// [-T10, T10], for every shift the maximize steps reach.
    function testTimesTenHintAtBound(uint8 sSeed, bool negative) external pure {
        uint256 s = bound(uint256(sSeed), 0, 75);
        uint256 x = T10 / 10 ** s;
        uint256 j = digitsOf(x) - 1;
        assertEq(s + j, 75);
        assertTrue(LibHalmosExact.timesTenHint(signed(x, negative), s));
        assertEq(digitsOf(x + 1), j + 1);
        assertTrue(LibHalmosExact.timesTenHint(signed(x + 1, negative), s));
        assertEq(digitsOf(x - 1), j + 1);
        assertTrue(LibHalmosExact.timesTenHint(signed(x - 1, negative), s));
    }

    /// True for every nonzero int256 at its digit count.
    function testMaximizeHints(uint256 seed, bool negative, uint8 jSeed) external pure {
        uint256 j = bound(uint256(jSeed), 0, 76);
        assertTrue(LibHalmosExact.maximizeHints(withDigits(seed, j, negative), j));
    }

    /// True for every nonzero int256 at its digit count.
    function testPackHints(uint256 seed, bool negative, uint8 nSeed) external pure {
        uint256 n = bound(uint256(nSeed), 0, 76);
        assertTrue(LibHalmosExact.packHints(withDigits(seed, n, negative), n));
    }

    /// Both hint filters at every threshold their steps compare against, the
    /// int224 and int256 bounds, and the fits-times-ten bound, both signs.
    function testHintsAtThresholds() external pure {
        uint256[] memory magnitudes = new uint256[](34);
        magnitudes[0] = 1;
        magnitudes[1] = 9;
        magnitudes[2] = 10;
        magnitudes[3] = 10 ** 37;
        magnitudes[4] = 10 ** 38 - 1;
        magnitudes[5] = 10 ** 38;
        magnitudes[6] = 10 ** 56;
        magnitudes[7] = 10 ** 57 - 1;
        magnitudes[8] = 10 ** 57;
        magnitudes[9] = 10 ** 65;
        magnitudes[10] = 10 ** 66 - 1;
        magnitudes[11] = 10 ** 66;
        magnitudes[12] = 10 ** 67 - 1;
        magnitudes[13] = 10 ** 67;
        magnitudes[14] = 2 ** 223 - 1;
        magnitudes[15] = 2 ** 223;
        magnitudes[16] = 2 ** 223 + 1;
        magnitudes[17] = 10 ** 71;
        magnitudes[18] = 10 ** 72 - 1;
        magnitudes[19] = 10 ** 72;
        magnitudes[20] = 10 ** 73 - 1;
        magnitudes[21] = 10 ** 74 - 1;
        magnitudes[22] = 10 ** 74;
        magnitudes[23] = 10 ** 75 - 1;
        magnitudes[24] = 10 ** 75;
        magnitudes[25] = 10 ** 76 - 1;
        magnitudes[26] = 10 ** 76;
        magnitudes[27] = T10;
        magnitudes[28] = T10 + 1;
        magnitudes[29] = 10 * T10;
        magnitudes[30] = 10 * T10 + 1;
        magnitudes[31] = 2 ** 255 - 2;
        magnitudes[32] = 2 ** 255 - 1;
        magnitudes[33] = 2 ** 255;
        for (uint256 i = 0; i < magnitudes.length; i++) {
            uint256 j = digitsOf(magnitudes[i]) - 1;
            if (magnitudes[i] < 2 ** 255) {
                assertTrue(LibHalmosExact.maximizeHints(signed(magnitudes[i], false), j));
                assertTrue(LibHalmosExact.packHints(signed(magnitudes[i], false), j));
            }
            assertTrue(LibHalmosExact.maximizeHints(signed(magnitudes[i], true), j));
            assertTrue(LibHalmosExact.packHints(signed(magnitudes[i], true), j));
        }
    }

    /// The low `bits` bits of x.
    function testConcrete(uint256 x, uint16 bitsSeed) external pure {
        uint256 bits = bound(uint256(bitsSeed), 0, 256);
        uint256 expected = bits == 256 ? x : x % 2 ** bits;
        assertEq(LibHalmosExact.concrete(x, bits), expected);
    }

    /// The widths the lemmas rebuild case indices with.
    function testConcreteLemmaWidths(uint256 x) external pure {
        assertEq(LibHalmosExact.concrete(x, 7), x % 128);
        assertEq(LibHalmosExact.concrete(x, 4), x % 16);
        assertEq(LibHalmosExact.concrete(x, 0), 0);
    }

    /// Against `LibExactFloat`'s exact comparison, within the exponents its
    /// digit arithmetic holds for.
    function testEqValueAgainstExact(int256 rc, int256 re, int256 sc, int256 se) external pure {
        re = bound(re, -(2 ** 254), 2 ** 254);
        se = bound(se, -(2 ** 254), 2 ** 254);
        bool expected;
        if (rc == 0 || sc == 0) {
            expected = rc == sc;
        } else {
            expected = (rc < 0) == (sc < 0)
                && LibExactFloat.cmpScaled(
                        LibExactFloat.u512(LibExactFloat.abs(rc)), re, LibExactFloat.u512(LibExactFloat.abs(sc)), se
                    ) == 0;
        }
        assertEq(LibHalmosExact.eqValue(rc, re, sc, se), expected);
    }

    /// Equal values d exponents apart for every d in [0, 76], in both orders;
    /// one unit, one exponent or the sign off is not equal.
    function testEqValueShifted(int256 sc, int256 se, uint8 dSeed) external pure {
        uint256 d = bound(uint256(dSeed), 0, 76);
        se = bound(se, -(2 ** 254), 2 ** 254);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 scale = int256(10 ** d);
        // Keeps rc and its neighbours one unit either side inside int256.
        sc = bound(sc, type(int256).min / scale + 1, type(int256).max / scale - 1);
        vm.assume(sc != 0);
        int256 rc = sc * scale;
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 re = se - int256(d);
        assertTrue(LibHalmosExact.eqValue(rc, re, sc, se));
        assertTrue(LibHalmosExact.eqValue(sc, se, rc, re));
        assertFalse(LibHalmosExact.eqValue(rc + 1, re, sc, se));
        assertFalse(LibHalmosExact.eqValue(rc - 1, re, sc, se));
        assertFalse(LibHalmosExact.eqValue(rc, re + 1, sc, se));
        assertFalse(LibHalmosExact.eqValue(rc, re - 1, sc, se));
        assertFalse(LibHalmosExact.eqValue(-rc, re, sc, se));
        assertFalse(LibHalmosExact.eqValue(rc, re, -sc, se));
    }

    /// Zero is zero at any exponent and nothing else.
    function testEqValueZero(int256 c, int256 e1, int256 e2) external pure {
        assertTrue(LibHalmosExact.eqValue(0, e1, 0, e2));
        vm.assume(c != 0);
        assertFalse(LibHalmosExact.eqValue(0, e1, c, e2));
        assertFalse(LibHalmosExact.eqValue(c, e1, 0, e2));
    }

    /// Nonzero values 78 or more exponents apart are never equal, however far
    /// apart within int256.
    function testEqValueFarApart(int256 rc, int256 re, int256 sc, int256 se) external pure {
        vm.assume(rc != 0 && sc != 0);
        re = bound(re, type(int256).min + 78, type(int256).max);
        se = bound(se, type(int256).min, re - 78);
        assertFalse(LibHalmosExact.eqValue(rc, re, sc, se));
        assertFalse(LibHalmosExact.eqValue(sc, se, rc, re));
    }

    function testEqValueConcrete() external pure {
        assertTrue(LibHalmosExact.eqValue(1, 1, 10, 0));
        assertTrue(LibHalmosExact.eqValue(10, 0, 1, 1));
        assertFalse(LibHalmosExact.eqValue(1, 0, 10, 0));
        assertTrue(LibHalmosExact.eqValue(12, 2, 1200, 0));
        assertFalse(LibHalmosExact.eqValue(12, 2, 1201, 0));
        assertFalse(LibHalmosExact.eqValue(12, 2, 1199, 0));
        assertTrue(LibHalmosExact.eqValue(-12, 2, -1200, 0));
        assertFalse(LibHalmosExact.eqValue(12, 2, -1200, 0));
        assertFalse(LibHalmosExact.eqValue(-12, 2, 1200, 0));
        int256 e76 = signed(10 ** 76, false);
        assertTrue(LibHalmosExact.eqValue(1, 76, e76, 0));
        assertTrue(LibHalmosExact.eqValue(e76, 0, 1, 76));
        assertTrue(LibHalmosExact.eqValue(1, 77, e76, 1));
        assertFalse(LibHalmosExact.eqValue(1, 77, e76, 0));
        assertFalse(LibHalmosExact.eqValue(1, 78, 1, 0));
        assertFalse(LibHalmosExact.eqValue(1, type(int256).max, 1, type(int256).min));
        assertFalse(LibHalmosExact.eqValue(1, type(int256).min, 1, type(int256).max));
        assertTrue(LibHalmosExact.eqValue(1, type(int256).max, 1, type(int256).max));
        assertTrue(LibHalmosExact.eqValue(type(int256).min, 0, type(int256).min, 0));
        assertTrue(LibHalmosExact.eqValue(type(int256).min, 5, type(int256).min, 5));
        assertFalse(LibHalmosExact.eqValue(type(int256).min, 0, type(int256).min / 10, 1));
        assertTrue(LibHalmosExact.eqValue(type(int256).max, 0, type(int256).max, 0));
        assertTrue(LibHalmosExact.eqValue(signed(10 * T10, false), 0, signed(T10, false), 1));
        assertTrue(LibHalmosExact.eqValue(signed(10 * T10, true), 0, signed(T10, true), 1));
        assertFalse(LibHalmosExact.eqValue(type(int256).max, 0, signed(T10, false), 1));
        // 2^254 times ten is 2^255 mod 2^256: a product that wraps onto the
        // other magnitude is not an equality, in either argument order.
        assertFalse(LibHalmosExact.eqValue(type(int256).min, 0, -(2 ** 254), 1));
        assertFalse(LibHalmosExact.eqValue(-(2 ** 254), 1, type(int256).min, 0));
    }

    /// The slice filters against bounds passed in, never set in the process
    /// environment: the cover tests of the sliced lemmas read it on other
    /// threads of the same run. Inclusive at both ends for `inSlice`, and
    /// `overlapsSlice` iff the block meets the slice.
    function testSliceBoundsInclusive() external pure {
        assertFalse(LibHalmosExact.inSliceOf(9, 10, 20));
        assertTrue(LibHalmosExact.inSliceOf(10, 10, 20));
        assertTrue(LibHalmosExact.inSliceOf(15, 10, 20));
        assertTrue(LibHalmosExact.inSliceOf(20, 10, 20));
        assertFalse(LibHalmosExact.inSliceOf(21, 10, 20));
        assertFalse(LibHalmosExact.overlapsSliceOf(0, 9, 10, 20));
        assertTrue(LibHalmosExact.overlapsSliceOf(0, 10, 10, 20));
        assertTrue(LibHalmosExact.overlapsSliceOf(10, 10, 10, 20));
        assertTrue(LibHalmosExact.overlapsSliceOf(12, 15, 10, 20));
        assertTrue(LibHalmosExact.overlapsSliceOf(20, 20, 10, 20));
        assertTrue(LibHalmosExact.overlapsSliceOf(20, 30, 10, 20));
        assertFalse(LibHalmosExact.overlapsSliceOf(21, 30, 10, 20));
        assertTrue(LibHalmosExact.overlapsSliceOf(0, type(uint256).max, 10, 20));

        assertFalse(LibHalmosExact.inSliceOf(737, 738, 738));
        assertTrue(LibHalmosExact.inSliceOf(738, 738, 738));
        assertFalse(LibHalmosExact.inSliceOf(739, 738, 738));
        assertTrue(LibHalmosExact.overlapsSliceOf(737, 747, 738, 738));
        assertFalse(LibHalmosExact.overlapsSliceOf(726, 736, 738, 738));
        assertFalse(LibHalmosExact.overlapsSliceOf(739, 749, 738, 738));
    }

    /// Unset (as in this run), the slice is every case.
    function testUnsetSliceIsEveryCase() external view {
        assertTrue(LibHalmosExact.inSlice(0));
        assertTrue(LibHalmosExact.inSlice(857));
        assertTrue(LibHalmosExact.inSlice(type(uint256).max));
        assertTrue(LibHalmosExact.overlapsSlice(0, 0));
        assertTrue(LibHalmosExact.overlapsSlice(type(uint256).max, type(uint256).max));
    }
}
