// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibExactFloat} from "test/lib/LibExactFloat.sol";

import {Test} from "forge-std-1.17.0/src/Test.sol";

/// #350: `add` and `sub` are the exact sum rounded once towards zero, checked
/// against `LibExactFloat.isNearestSum`, which takes the exact sum
/// without the int256 unit `isSumResult` works in.
contract LibDecimalFloatRoundOnceTest is Test {
    using LibDecimalFloat for Float;

    function addExternal(Float a, Float b) external pure returns (Float) {
        return a.add(b);
    }

    function subExternal(Float a, Float b) external pure returns (Float) {
        return a.sub(b);
    }

    function checkSumRoundOnce(int256 ca, int256 ea, int256 cb, int256 eb, Float result) internal pure {
        (int256 rc, int256 re) = result.unpack();
        assertTrue(LibExactFloat.isNearestSum(ca, ea, cb, eb, rc, re), "once towards zero");
    }

    function testAddRoundOnce(Float a, Float b) external view {
        (int256 ca, int256 ea) = a.unpack();
        (int256 cb, int256 eb) = b.unpack();
        vm.assume(!LibExactFloat.addOverflows(ca, ea, cb, eb));
        checkSumRoundOnce(ca, ea, cb, eb, this.addExternal(a, b));
    }

    /// As `testAddRoundOnce`, for `a + -b`.
    function testSubRoundOnce(Float a, Float b) external view {
        (int256 ca, int256 ea) = a.unpack();
        (int256 cb, int256 eb) = b.unpack();
        vm.assume(!LibExactFloat.addOverflows(ca, ea, -cb, eb));
        checkSumRoundOnce(ca, ea, -cb, eb, this.subExternal(a, b));
    }

    /// As `testAddRoundOnce`, with the operands' digits overlapping or
    /// adjacent, so aligning sheds some of `b`'s.
    function testAddRoundOnceNearby(int224 ca, int32 ea, int224 cb, uint256 gap) external view {
        int256 eb = int256(ea) - int256(bound(gap, 0, 100));
        vm.assume(eb >= type(int32).min);
        Float a = LibDecimalFloat.packLossless(ca, ea);
        Float b = LibDecimalFloat.packLossless(cb, eb);
        vm.assume(!LibExactFloat.addOverflows(ca, ea, cb, eb));
        checkSumRoundOnce(ca, ea, cb, eb, this.addExternal(a, b));
    }

    /// A non-zero `b` of the other sign wholly below `a`'s int256 unit takes
    /// the sum to the Float before `a`, towards zero.
    function testAddCancelBelowUnitRoundOnce(int224 ca, int32 ea, int224 cb, uint256 gap) external pure {
        vm.assume(ca != 0 && cb != 0);
        cb = (ca < 0) == (cb < 0) ? (cb == type(int224).min ? type(int224).max : -cb) : cb;
        int256 top = int256(ea) + LibExactFloat.digits(LibExactFloat.u512(LibExactFloat.abs(ca)));
        int256 eb =
            top - 77 - LibExactFloat.digits(LibExactFloat.u512(LibExactFloat.abs(cb))) - int256(bound(gap, 0, 1000));
        vm.assume(eb >= type(int32).min);
        Float a = LibDecimalFloat.packLossless(ca, ea);
        Float result = a.add(LibDecimalFloat.packLossless(cb, eb));
        (int256 rc, int256 re) = result.unpack();
        assertTrue(LibExactFloat.isNearestSum(ca, ea, cb, eb, rc, re), "once towards zero");
        assertTrue(ca < 0 ? result.gt(a) : result.lt(a), "before a");
    }

    /// `1e100 + -1` is `(1e67 - 1)e33`, `1e100 - (1e33 + 1)` is
    /// `1e100 - 2e33` and `1 - 1e-100` is 67 nines after the point.
    function testAddSubRoundOnceExamples() external pure {
        Float big = LibDecimalFloat.packLossless(1, 100);
        Float r = big.add(LibDecimalFloat.packLossless(-1, 0));
        assertTrue(r.eq(LibDecimalFloat.packLossless(1e67 - 1, 33)), "1e100 + -1");
        assertTrue(LibExactFloat.isNearestSum(1, 100, -1, 0, 1e67 - 1, 33), "oracle 1e100 + -1");
        assertFalse(LibExactFloat.isNearestSum(1, 100, -1, 0, 1, 100), "oracle 1e100 + -1 away");

        r = big.sub(LibDecimalFloat.packLossless(1e33 + 1, 0));
        assertTrue(r.eq(LibDecimalFloat.packLossless(1e67 - 2, 33)), "1e100 - (1e33 + 1)");
        assertTrue(LibExactFloat.isNearestSum(1, 100, -(1e33 + 1), 0, 1e67 - 2, 33), "oracle 1e100 - (1e33 + 1)");
        assertFalse(LibExactFloat.isNearestSum(1, 100, -(1e33 + 1), 0, 1e67 - 1, 33), "oracle 1e100 - (1e33 + 1) away");

        Float one = LibDecimalFloat.packLossless(1, 0);
        r = one.sub(LibDecimalFloat.packLossless(1, -100));
        assertTrue(r.eq(LibDecimalFloat.packLossless(1e67 - 1, -67)), "1 - 1e-100");
        assertTrue(LibExactFloat.isNearestSum(1, 0, -1, -100, 1e67 - 1, -67), "oracle 1 - 1e-100");
        assertFalse(LibExactFloat.isNearestSum(1, 0, -1, -100, 1, 0), "oracle 1 - 1e-100 away");
    }
}
