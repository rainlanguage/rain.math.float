// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";

contract LibDecimalFloatMinTest is Test {
    using LibDecimalFloat for Float;

    /// x.min(x)
    function testMinX(Float x) external pure {
        Float y = x.min(x);
        assertTrue(y.eq(x), "x.min(x) != x");
    }

    /// x.min(y) == y.min(x)
    function testMinXY(Float x, Float y) external pure {
        // forge-lint: disable-next-line(mixed-case-variable)
        Float minXY = x.min(y);
        // forge-lint: disable-next-line(mixed-case-variable)
        Float minYX = y.min(x);
        assertTrue(minXY.eq(minYX), "minXY != minYX");
    }

    /// x.min(y) for x == y
    function testMinXYEqual(Float x) external pure {
        Float y = x;
        Float z = x.min(y);
        assertTrue(z.eq(x), "x.min(y) != x");
        assertTrue(z.eq(y), "x.min(y) != y");
    }

    /// `a.min(b)` returns the operand that `a < b ? a : b` picks, decided by
    /// exact value: `b` on a tie, bit for bit.
    function checkMinExact(Float a, Float b) internal pure {
        (int256 ca, int256 ea) = a.unpack();
        (int256 cb, int256 eb) = b.unpack();
        Float expected = LibTestExactDecimal.cmpParts(ca, ea, cb, eb) < 0 ? a : b;
        assertEq(Float.unwrap(a.min(b)), Float.unwrap(expected));
    }

    function testMinExact(Float a, Float b) external pure {
        checkMinExact(a, b);
    }

    function testMinExactSameExponent(int224 ca, int224 cb, int32 e) external pure {
        checkMinExact(LibDecimalFloat.packLossless(ca, e), LibDecimalFloat.packLossless(cb, e));
    }

    function testMinExactNearExponents(int224 ca, int224 cb, int32 e, int8 d) external pure {
        int256 eb = bound(int256(e) + d, type(int32).min, type(int32).max);
        checkMinExact(LibDecimalFloat.packLossless(ca, e), LibDecimalFloat.packLossless(cb, eb));
    }

    function checkMinExample(int256 ca, int256 ea, int256 cb, int256 eb, bool expectA) internal pure {
        Float a = LibDecimalFloat.packLossless(ca, ea);
        Float b = LibDecimalFloat.packLossless(cb, eb);
        assertEq(Float.unwrap(a.min(b)), Float.unwrap(expectA ? a : b));
    }

    function testMinExamples() external pure {
        checkMinExample(1, 0, 2, 0, true);
        checkMinExample(2, 0, 1, 0, false);
        checkMinExample(-1, 0, -2, 0, false);
        checkMinExample(-2, 0, -1, 0, true);
        checkMinExample(0, 0, -1, 0, false);
        checkMinExample(-1, -100, 0, 0, true);
        // 0.1 < 0.99
        checkMinExample(1, -1, 99, -2, true);
        // 10 > 9.9
        checkMinExample(1, 1, 99, -1, false);
        // -10 < -9.9
        checkMinExample(-1, 1, -99, -1, true);
        // 123456789 < 123456789.1
        checkMinExample(123456789, 0, 1234567891, -1, true);
        checkMinExample(type(int224).max, type(int32).max, type(int224).min, type(int32).max, false);
        checkMinExample(1, type(int32).min, -1, type(int32).max, false);
        // Ties of distinct representations return b.
        checkMinExample(1, 0, 10, -1, false);
        checkMinExample(10, -1, 1, 0, false);
        checkMinExample(-1, 0, -10, -1, false);
        checkMinExample(0, 5, 0, -5, false);
    }
}
