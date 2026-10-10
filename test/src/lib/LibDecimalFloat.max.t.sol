// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";

contract LibDecimalFloatMaxTest is Test {
    using LibDecimalFloat for Float;

    /// x.max(x)
    function testMaxX(Float x) external pure {
        Float y = x.max(x);
        assertTrue(y.eq(x), "x.max(x) != x");
    }

    /// x.max(y) == y.max(x)
    function testMaxXY(Float x, Float y) external pure {
        // forge-lint: disable-next-line(mixed-case-variable)
        Float maxXY = x.max(y);
        // forge-lint: disable-next-line(mixed-case-variable)
        Float maxYX = y.max(x);
        assertTrue(maxXY.eq(maxYX), "maxXY != maxYX");
    }

    /// x.max(y) for x == y
    function testMaxXYEqual(Float x) external pure {
        Float y = x;
        Float z = x.max(y);
        assertTrue(z.eq(x), "x.max(y) != x");
        assertTrue(z.eq(y), "x.max(y) != y");
    }

    /// `a.max(b)` returns the operand that `a > b ? a : b` picks, decided by
    /// exact value: `b` on a tie, bit for bit.
    function checkMaxExact(Float a, Float b) internal pure {
        (int256 ca, int256 ea) = a.unpack();
        (int256 cb, int256 eb) = b.unpack();
        Float expected = LibTestExactDecimal.cmpParts(ca, ea, cb, eb) > 0 ? a : b;
        assertEq(Float.unwrap(a.max(b)), Float.unwrap(expected));
    }

    function testMaxExact(Float a, Float b) external pure {
        checkMaxExact(a, b);
    }

    function testMaxExactSameExponent(int224 ca, int224 cb, int32 e) external pure {
        checkMaxExact(LibDecimalFloat.packLossless(ca, e), LibDecimalFloat.packLossless(cb, e));
    }

    function testMaxExactNearExponents(int224 ca, int224 cb, int32 e, int8 d) external pure {
        int256 eb = bound(int256(e) + d, type(int32).min, type(int32).max);
        checkMaxExact(LibDecimalFloat.packLossless(ca, e), LibDecimalFloat.packLossless(cb, eb));
    }

    function checkMaxExample(int256 ca, int256 ea, int256 cb, int256 eb, bool expectA) internal pure {
        Float a = LibDecimalFloat.packLossless(ca, ea);
        Float b = LibDecimalFloat.packLossless(cb, eb);
        assertEq(Float.unwrap(a.max(b)), Float.unwrap(expectA ? a : b));
    }

    function testMaxExamples() external pure {
        checkMaxExample(1, 0, 2, 0, false);
        checkMaxExample(2, 0, 1, 0, true);
        checkMaxExample(-1, 0, -2, 0, true);
        checkMaxExample(-2, 0, -1, 0, false);
        checkMaxExample(0, 0, -1, 0, true);
        checkMaxExample(-1, -100, 0, 0, false);
        // 0.1 < 0.99
        checkMaxExample(1, -1, 99, -2, false);
        // 10 > 9.9
        checkMaxExample(1, 1, 99, -1, true);
        // -10 < -9.9
        checkMaxExample(-1, 1, -99, -1, false);
        // 123456789 < 123456789.1
        checkMaxExample(123456789, 0, 1234567891, -1, false);
        checkMaxExample(type(int224).max, type(int32).max, type(int224).min, type(int32).max, true);
        checkMaxExample(1, type(int32).min, -1, type(int32).max, true);
        // Ties of distinct representations return b.
        checkMaxExample(1, 0, 10, -1, false);
        checkMaxExample(10, -1, 1, 0, false);
        checkMaxExample(-1, 0, -10, -1, false);
        checkMaxExample(0, 5, 0, -5, false);
    }
}
