// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";

import {Test} from "forge-std-1.17.0/src/Test.sol";

/// `add`'s documented rounding (#340), worked by hand: round the exact sum to
/// the larger operand's int256 unit, towards zero when the magnitudes add and
/// away from zero when they cancel, then pack towards zero. Each case pins the
/// library's result and that `LibTestExactDecimal.isSumResult` accepts it and
/// rejects the Float on its other side.
contract LibDecimalFloatAddRuleTest is Test {
    using LibDecimalFloat for Float;

    function checkCase(int256 ca, int256 ea, int256 cb, int256 eb, int256 rc, int256 re, int256 otherC, int256 otherE)
        internal
        pure
    {
        Float sum = LibDecimalFloat.packLossless(ca, ea).add(LibDecimalFloat.packLossless(cb, eb));
        assertTrue(sum.eq(LibDecimalFloat.packLossless(rc, re)), "library");
        assertTrue(LibTestExactDecimal.isSumResult(ca, ea, cb, eb, rc, re), "accepted");
        assertFalse(LibTestExactDecimal.isSumResult(ca, ea, cb, eb, otherC, otherE), "other rejected");
    }

    /// `1e100 - 1`: unit `1e24`, away from zero to `1e100`.
    function testAddRuleCancelAway() external pure {
        checkCase(1, 100, -1, 0, 1, 100, 1e67 - 1, 33);
    }

    /// `-1 + 1e100`: the larger operand is the second.
    function testAddRuleCancelLargerSecond() external pure {
        checkCase(-1, 0, 1, 100, 1, 100, 1e67 - 1, 33);
    }

    /// `-1e100 + 1`: negative, away from zero to `-1e100`.
    function testAddRuleCancelAwayNegative() external pure {
        checkCase(-1, 100, 1, 0, -1, 100, -(1e67 - 1), 33);
    }

    /// `1e76 - 1000000001.5`: unit `1`, away to `1e76 - 1000000001`, packed
    /// towards zero to `(10^67 - 2)e9`, below the exact sum.
    function testAddRuleCancelAwayThenPackTowards() external pure {
        checkCase(1e66, 10, -10000000015, -1, 1e67 - 2, 9, 1e67 - 1, 9);
    }

    /// `1e100 - (1e33 + 1)`: away at `1e24` to `1e100 - 1e33`, which packs
    /// exactly.
    function testAddRuleCancelPartialDigitAway() external pure {
        checkCase(1, 100, -(1e33 + 1), 0, 1e67 - 1, 33, 1e67 - 2, 33);
    }

    /// `1e100 - 1.7e33`: exact at `1e24`, packed towards zero.
    function testAddRuleCancelExactAtUnit() external pure {
        checkCase(1, 100, -17, 32, 1e67 - 2, 33, 1e67 - 1, 33);
    }

    /// `1e100 - 1.5e24`: one and a half units, away to `1e100 - 1e24`, packed
    /// towards zero to `1e100 - 1e33`.
    function testAddRuleCancelUnitAndAHalf() external pure {
        checkCase(1, 100, -15e61, -38, 1e67 - 1, 33, 1, 100);
    }

    /// `1 - 1.5e-76`: unit `1e-76`, away to `1 - 1e-76`, packed towards zero.
    function testAddRuleCancelAwayThenPack() external pure {
        checkCase(1, 0, -15, -77, 1e67 - 1, -67, 1, 0);
    }

    /// `1 - 1e-100`: away to `1`.
    function testAddRuleCancelTinyAway() external pure {
        checkCase(1, 0, -1, -100, 1, 0, 1e67 - 1, -67);
    }

    /// `6 - 1.5e-76`: `6 × 10^76` exceeds int256, so the unit is `1e-75`, and
    /// the sum rounds away to `6`. At `1e-76` it would round to `6 - 1e-76`
    /// and pack to 66 nines after `5.`.
    function testAddRuleCancelUnit76Digits() external pure {
        checkCase(6, 0, -15, -77, 6, 0, 6e66 - 1, -66);
    }

    /// `1e20 - 1.5e11`: both within one unit grid, exact.
    function testAddRuleCancelExact() external pure {
        checkCase(1e20, 0, -15, 10, 9999999985, 10, 9999999986, 10);
    }

    /// `5 - 5` is zero.
    function testAddRuleCancelToZero() external pure {
        checkCase(5, 0, -5, 0, 0, 0, 1, -100);
    }

    /// `1e100 + 1e-100`: towards zero to `1e100`.
    function testAddRuleSameSignTowards() external pure {
        checkCase(1, 100, 1, -100, 1, 100, 1e67 + 1, 33);
    }

    /// `1e100 + 9.999999995e32`: towards zero at `1e24` to
    /// `1e100 + 999999999e24`, packed to `1e100`. Away from zero would reach
    /// `1e100 + 1e33`.
    function testAddRuleSameSignPartialUnitTowards() external pure {
        checkCase(1, 100, 9999999995, 23, 1, 100, 1e67 + 1, 33);
    }

    /// `1e100 + 1.7e33`: exact at `1e24`, packed towards zero.
    function testAddRuleSameSignExactAtUnit() external pure {
        checkCase(1, 100, 17, 32, 1e67 + 1, 33, 1e67 + 2, 33);
    }

    /// A zero operand leaves the other's parts as they are.
    function testAddRuleZeroOperand() external pure {
        assertTrue(LibTestExactDecimal.isSumResult(0, 5, 3, 2, 3, 2), "zero a");
        assertFalse(LibTestExactDecimal.isSumResult(0, 5, 3, 2, 3, 5), "zero a, a's exponent");
        assertTrue(LibTestExactDecimal.isSumResult(3, 2, 0, 5, 3, 2), "zero b");
        assertFalse(LibTestExactDecimal.isSumResult(3, 2, 0, 5, 3, 5), "zero b, b's exponent");
    }

    /// `a` with under 67 digits, and `b` reaching `s` digits below `a`'s int256
    /// unit with a non-zero remainder there. `b`'s part at or above the unit
    /// is `q` units, where `q` is a multiple of `10^10` when the magnitudes
    /// cancel and one less than one when they add. Step 1 then lands on a
    /// multiple of `10^10` units when cancelling and one unit below one when
    /// adding, and packing's step is at most `10^10` units, so rounding the
    /// other way at step 1 moves the packed result.
    function roundingOperands(int256 ca, int256 ea, bool sameSign, uint256 q, uint256 s, uint256 r)
        internal
        pure
        returns (Float, int256, int256)
    {
        s = bound(s, 1, 56);
        // forge-lint: disable-next-line(unsafe-typecast)
        q = bound(q, 1, 10 ** (56 - s)) * 1e10;
        if (sameSign) {
            q -= 1;
        }
        r = bound(r, 1, 10 ** s - 1);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 eb = LibTestExactDecimal.int256Unit(ca, ea) - int256(s);
        vm.assume(eb >= type(int32).min);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 magnitude = int256(q * 10 ** s + r);
        int256 cb = (ca < 0) == sameSign ? -magnitude : magnitude;
        return (LibDecimalFloat.packLossless(ca, ea), cb, eb);
    }

    function boundA(int256 ca) internal pure returns (int256) {
        ca = bound(ca, -(1e66 - 1), 1e66 - 1);
        vm.assume(ca != 0);
        return ca;
    }

    /// `add` lands where the rule puts it when the smaller operand has a
    /// fraction of a unit.
    function testAddRuleFractionOfUnit(int256 ca, int32 ea, bool sameSign, uint256 q, uint256 s, uint256 r)
        external
        pure
    {
        ca = boundA(ca);
        (Float a, int256 cb, int256 eb) = roundingOperands(ca, ea, sameSign, q, s, r);
        (int256 rc, int256 re) = a.add(LibDecimalFloat.packLossless(cb, eb)).unpack();
        assertTrue(LibTestExactDecimal.isSumResult(ca, ea, cb, eb, rc, re), "add");
    }

    /// As `testAddRuleFractionOfUnit`, through `sub` of the negated operand.
    function testSubRuleFractionOfUnit(int256 ca, int32 ea, bool sameSign, uint256 q, uint256 s, uint256 r)
        external
        pure
    {
        ca = boundA(ca);
        (Float a, int256 cb, int256 eb) = roundingOperands(ca, ea, sameSign, q, s, r);
        (int256 rc, int256 re) = a.sub(LibDecimalFloat.packLossless(-cb, eb)).unpack();
        assertTrue(LibTestExactDecimal.isSumResult(ca, ea, cb, eb, rc, re), "sub");
    }

    /// As `testAddRuleFractionOfUnit` with the magnitudes adding past int256:
    /// `a`'s 66 digits at the int256 unit are within `10^14` of
    /// `type(int256).max`.
    function testAddRuleFractionOfUnitPastInt256(uint256 k, bool negative, int32 ea, uint256 q, uint256 s, uint256 r)
        external
        pure
    {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 ca = type(int256).max / 1e11 - int256(bound(k, 0, 1000));
        if (negative) {
            ca = -ca;
        }
        (Float a, int256 cb, int256 eb) = roundingOperands(ca, ea, true, q, s, r);
        (int256 rc, int256 re) = a.add(LibDecimalFloat.packLossless(cb, eb)).unpack();
        assertTrue(LibTestExactDecimal.isSumResult(ca, ea, cb, eb, rc, re), "add");
    }
}
