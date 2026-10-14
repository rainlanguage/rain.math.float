// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloatImplementation} from "../../../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibDecimalFloatImplementationPreShortfall} from "../../../lib/LibDecimalFloatImplementationPreShortfall.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {MaximizeOverflow, ExponentOverflow, DivisionByZero} from "../../../../src/error/ErrDecimalFloat.sol";
import {LibExactFloat} from "../../../lib/LibExactFloat.sol";

/// Wherever the baseline returns, the live library returns the same bytes, and
/// wherever the baseline reverts, the live library reverts the same bytes,
/// except in the floor shortfall, carry (#394), cancelling (#350) and
/// int256.min subtrahend (#459) classes each `check*` names. Those are asserted
/// against an oracle. Equivalence only: the baseline carries the mixed-sign add
/// rounding of #340, so agreement is not a value check. `testAddPacked`,
/// `testSubPacked`, `testDivPacked` and `testInvMem` check values against exact
/// math.
contract LibDecimalFloatImplementationPreShortfallEquivalenceTest is Test {
    /// Lifts a floor operand clear of every maximize shift.
    int256 constant SHIFT = 200;

    function preShortfallMaximize(int256 c, int256 e) external pure returns (int256, int256, bool) {
        return LibDecimalFloatImplementationPreShortfall.maximize(c, e);
    }

    function liveMaximize(int256 c, int256 e) external pure returns (int256, int256, int256) {
        return LibDecimalFloatImplementation.maximize(c, e);
    }

    function preShortfallMaximizeFull(int256 c, int256 e) external pure returns (int256, int256) {
        return LibDecimalFloatImplementationPreShortfall.maximizeFull(c, e);
    }

    function liveMaximizeFull(int256 c, int256 e) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.maximizeFull(c, e);
    }

    function preShortfallDiv(int256 a, int256 ea, int256 b, int256 eb) external pure returns (int256, int256) {
        return LibDecimalFloatImplementationPreShortfall.div(a, ea, b, eb);
    }

    function liveDiv(int256 a, int256 ea, int256 b, int256 eb) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.div(a, ea, b, eb);
    }

    function preShortfallAdd(int256 a, int256 ea, int256 b, int256 eb) external pure returns (int256, int256) {
        return LibDecimalFloatImplementationPreShortfall.add(a, ea, b, eb);
    }

    function liveAdd(int256 a, int256 ea, int256 b, int256 eb) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.add(a, ea, b, eb);
    }

    function preShortfallSub(int256 a, int256 ea, int256 b, int256 eb) external pure returns (int256, int256) {
        return LibDecimalFloatImplementationPreShortfall.sub(a, ea, b, eb);
    }

    function liveSub(int256 a, int256 ea, int256 b, int256 eb) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.sub(a, ea, b, eb);
    }

    function preShortfallInv(int256 c, int256 e) external pure returns (int256, int256) {
        return LibDecimalFloatImplementationPreShortfall.inv(c, e);
    }

    function liveInv(int256 c, int256 e) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.inv(c, e);
    }

    function run(bytes memory data) internal view returns (bool, bytes memory) {
        return address(this).staticcall(data);
    }

    function pair(bytes memory ret) internal pure returns (int256, int256) {
        return abi.decode(ret, (int256, int256));
    }

    function selector(bytes memory ret) internal pure returns (bytes4 s) {
        if (ret.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            s := mload(add(ret, 0x20))
        }
    }

    function nearFloor(uint256 x) internal pure returns (int256) {
        return type(int256).min + int256(bound(x, 0, 200));
    }

    /// Spreads coefficients over every digit count, which sets the shortfall.
    function digits(int256 c, uint8 shift) internal pure returns (int256) {
        return c >> shift;
    }

    /// Independent of both libraries: multiply by 10 until it would overflow.
    function slowMaximize(int256 c) internal pure returns (int256, int256 shift) {
        if (c == 0) return (0, 0);
        unchecked {
            while ((c * 10) / 10 == c) {
                c *= 10;
                shift++;
            }
        }
        return (c, shift);
    }

    function slowShortfall(int256 c, int256 e) internal pure returns (int256) {
        if (e > type(int256).min + 77) return 0;
        (, int256 shift) = slowMaximize(c);
        unchecked {
            int256 room = e - type(int256).min;
            return shift > room ? shift - room : int256(0);
        }
    }

    function atFloor(int256 a, int256 ea, int256 b, int256 eb) internal pure returns (bool) {
        return slowShortfall(a, ea) > 0 || slowShortfall(b, eb) > 0;
    }

    function isPowerOfTen(int256 c) internal pure returns (bool) {
        if (c == 0) return false;
        while (c % 10 == 0) {
            c /= 10;
        }
        return c == 1 || c == -1;
    }

    /// `qe + ea - eb > type(int256).max` for `ea > 0 > eb`, without overflow.
    function exponentPastMax(int256 ea, int256 eb, int256 qe) internal pure returns (bool) {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 d = uint256(ea) + (eb == type(int256).min ? uint256(1) << 255 : uint256(-eb));
        // forge-lint: disable-next-line(unsafe-typecast)
        return qe >= 0 ? d + uint256(qe) > uint256(type(int256).max) : d > uint256(type(int256).max) + uint256(-qe);
    }

    function checkMaximize(int256 c, int256 e) internal view {
        (int256 mc, int256 me, bool full) = this.preShortfallMaximize(c, e);
        (int256 pc, int256 pe, int256 shortfall) = this.liveMaximize(c, e);
        assertEq(shortfall, slowShortfall(c, e), "shortfall");
        if (shortfall == 0) {
            assertEq(pc, mc, "coefficient");
            assertEq(pe, me, "exponent");
            assertTrue(full, "full");
            return;
        }
        // By design: the baseline stops short of the floor, the live library
        // fills the coefficient and reports the digits the exponent could not
        // take.
        assertEq(pe, type(int256).min, "floor");
        int256 extra = me - type(int256).min + shortfall;
        assertTrue(extra > 0 && extra <= 77, "extra digits");
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(mc * int256(10 ** uint256(extra)), pc, "same value");
    }

    function testPreShortfallEquivalenceMaximize(int256 c, int256 e, uint8 shift) external view {
        checkMaximize(digits(c, shift), e);
    }

    function testPreShortfallEquivalenceMaximizeNearFloor(int256 c, uint256 e, uint8 shift) external view {
        checkMaximize(digits(c, shift), nearFloor(e));
    }

    function testPreShortfallEquivalenceMaximizePacked(int224 c, int32 e) external view {
        checkMaximize(c, e);
    }

    function checkMaximizeFull(int256 c, int256 e) internal view {
        (bool mOk, bytes memory m) = run(abi.encodeCall(this.preShortfallMaximizeFull, (c, e)));
        (bool pOk, bytes memory p) = run(abi.encodeCall(this.liveMaximizeFull, (c, e)));
        if (slowShortfall(c, e) == 0) {
            assertTrue(mOk && pOk, "both return");
            assertEq(p, m, "same result");
            return;
        }
        // By design: any shortfall reverts, including where the baseline
        // returned a 76 digit coefficient it stopped at the floor.
        assertFalse(pOk, "reverts");
        assertEq(p, abi.encodeWithSelector(MaximizeOverflow.selector, c, e), "revert data");
        if (!mOk) assertEq(m, p, "same revert");
    }

    function testPreShortfallEquivalenceMaximizeFull(int256 c, int256 e, uint8 shift) external view {
        checkMaximizeFull(digits(c, shift), e);
    }

    function testPreShortfallEquivalenceMaximizeFullNearFloor(int256 c, uint256 e, uint8 shift) external view {
        checkMaximizeFull(digits(c, shift), nearFloor(e));
    }

    function testPreShortfallEquivalenceMaximizeFullPacked(int224 c, int32 e) external view {
        checkMaximizeFull(c, e);
    }

    /// The live library's div against the parts its NatSpec states and the
    /// exact quotient they truncate (#368).
    function checkDivExact(int256 a, int256 ea, int256 b, int256 eb, bool ok, bytes memory ret) internal pure {
        if (b == 0) {
            assertFalse(ok, "divide by zero");
            assertEq(ret, abi.encodeWithSelector(DivisionByZero.selector, a, ea), "DivisionByZero");
            return;
        }
        (bool overflows, int256 ec, int256 ee) = LibExactFloat.divPartsWide(a, ea, b, eb);
        if (overflows) {
            assertFalse(ok, "exact div overflows");
            assertEq(selector(ret), ExponentOverflow.selector, "div ExponentOverflow");
            return;
        }
        assertTrue(ok, "exact div returns");
        (int256 c, int256 e) = pair(ret);
        assertEq(c, ec, "exact div coefficient");
        assertEq(e, ee, "exact div exponent");
        assertTrue(LibExactFloat.isTruncatedQuotient(a, ea, b, eb, c, e), "truncated quotient");
    }

    function checkDiv(int256 a, int256 ea, int256 b, int256 eb) internal view {
        (bool mOk, bytes memory m) = run(abi.encodeCall(this.preShortfallDiv, (a, ea, b, eb)));
        (bool pOk, bytes memory p) = run(abi.encodeCall(this.liveDiv, (a, ea, b, eb)));
        checkDivExact(a, ea, b, eb, pOk, p);
        if (mOk == pOk && keccak256(m) == keccak256(p)) return;

        if (!pOk) {
            // By design: the quotient exponent is past type(int256).max and the
            // live library reverts, where the baseline either wraps it or
            // reverts MaximizeOverflow on a ±1 divisor at the floor (#291).
            assertEq(selector(p), ExponentOverflow.selector, "live overflow");
            assertTrue(ea > 0 && eb < 0, "signs");
            (int256 qc, int256 qe) = this.preShortfallDiv(a, 0, b, 0);
            assertTrue(exponentPastMax(ea, eb, qe), "true exponent past max");
            if (mOk) {
                (int256 mc, int256 me) = pair(m);
                assertTrue(me < 0, "baseline wrapped");
                // #291: a power of ten divisor the baseline cannot lift to 1e75
                // at the floor gets the scale a digit below it, so the quotient
                // sheds a digit, whatever the numerator's length. Off the
                // floor, a positive 2^255 quotient has shed it already.
                (int256 maxA,) = slowMaximize(a);
                if (slowShortfall(b, eb) > 1 && isPowerOfTen(b) && !(maxA == type(int256).min && b < 0)) {
                    qc /= 10;
                    qe += 1;
                }
                unchecked {
                    assertTrue(
                        LibDecimalFloatImplementation.eq(mc, me - ea + eb, qc, qe), "baseline is the quotient mod 2^256"
                    );
                }
            } else if (selector(m) == bytes4(keccak256("Panic(uint256)"))) {
                // #645: a positive quotient past int256.max sheds a digit in
                // the baseline's `unabsUnsignedMulOrDivLossy`, whose checked
                // `exponent + 1` panics at type(int256).max.
                assertEq(m, abi.encodeWithSignature("Panic(uint256)", 0x11), "baseline panics on overflow");
                assertTrue((a < 0) == (b < 0), "positive quotient");
            } else {
                assertEq(selector(m), MaximizeOverflow.selector, "baseline MaximizeOverflow");
                assertTrue(b == 1 || b == -1, "divisor is one");
                assertTrue(slowShortfall(b, eb) > 0, "divisor at the floor");
            }
            return;
        }

        // By design (#368): a positive 2^255 quotient below the floor. The
        // baseline sheds a digit to fit int256 before it sheds to the floor, so
        // it truncates one digit more and lifts the exponent off the floor.
        (int256 pc, int256 pe) = pair(p);
        if (a == type(int256).min && b < 0 && isPowerOfTen(b) && pe == type(int256).min) {
            assertTrue(mOk, "baseline returns");
            assertEq(
                m, pc < 10 ? abi.encode(int256(0), int256(0)) : abi.encode(pc / 10, pe + 1), "baseline sheds one more"
            );
            return;
        }

        // By design: the baseline reverts or keeps fewer digits (#291, #292),
        // the live library matches the baseline on the same operands lifted off
        // the floor.
        assertTrue(atFloor(a, ea, b, eb), "differs off the floor");
        assertTrue(ea <= type(int256).max - SHIFT && eb <= type(int256).max - SHIFT, "liftable");
        (bool sOk, bytes memory s) = run(abi.encodeCall(this.preShortfallDiv, (a, ea + SHIFT, b, eb + SHIFT)));
        assertTrue(sOk, "lifted baseline returns");
        assertEq(p, s, "live matches lifted baseline");
    }

    function testPreShortfallEquivalenceDiv(int256 a, int256 ea, int256 b, int256 eb, uint8 sa, uint8 sb)
        external
        view
    {
        checkDiv(digits(a, sa), ea, digits(b, sb), eb);
    }

    function testPreShortfallEquivalenceDivNearFloor(
        int256 a,
        uint256 ea,
        int256 b,
        uint256 eb,
        uint8 sa,
        uint8 sb,
        int256 other,
        uint8 which
    ) external view {
        int256 expA = which % 3 == 1 ? other : nearFloor(ea);
        int256 expB = which % 3 == 2 ? other : nearFloor(eb);
        checkDiv(digits(a, sa), expA, digits(b, sb), expB);
    }

    /// #320: the baseline returns 2^255 / 10 for type(int256).min over -1 at
    /// the floor, the same digits it returns off the floor, and the live
    /// library reverts.
    function testPreShortfallEquivalenceDivMinByMinusOneAtFloor() external {
        int256 min = type(int256).min;
        int256 ea = 17810781030204754479236433;
        int256 eb = min + 34;
        (int256 mc, int256 me) = this.preShortfallDiv(min, ea, -1, eb);
        assertEq(mc, -(min / 10), "baseline coefficient");
        unchecked {
            assertEq(me, 1 + ea - eb, "baseline exponent wraps");
        }
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, min, ea - 34));
        this.liveDiv(min, ea, -1, eb);
        checkDiv(min, ea, -1, eb);
    }

    /// CI on #321: a 76 digit numerator over a power of ten divisor at the
    /// floor. The baseline sheds its last digit, so the quotient is not 2^252 -
    /// 1.
    function testPreShortfallEquivalenceDivFloorPowerOfTenShedsShortNumerator() external {
        int256 min = type(int256).min;
        int256 a = (type(int256).max - 1) >> 3;
        assertEq(a, int256(2 ** 252 - 1), "numerator");
        int256 ea = 32178700140544239384795735284313615056211;
        int256 eb = min + 6;
        (int256 mc, int256 me) = this.preShortfallDiv(a, ea, -1, eb);
        assertEq(mc, -(a / 10), "baseline sheds the last digit");
        unchecked {
            assertEq(me, 1 + ea - eb, "baseline exponent wraps");
        }
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, a, ea - 6));
        this.liveDiv(a, ea, -1, eb);
        checkDiv(a, ea, -1, eb);
        this.testPreShortfallEquivalenceDivNearFloor(
            57896044618658097711785492504343953926634992332820282019728792003956564819966,
            368367291179877007172175548793829148665894,
            -3153459,
            1043330888898218908680,
            3,
            94,
            32178700140544239384795735284313615056211,
            1
        );
    }

    /// A divisor one digit short of 1e76 at the floor is 1e75 to the baseline,
    /// which is full, so the baseline keeps every digit of a 77 digit
    /// numerator.
    function testPreShortfallEquivalenceDivFloorPowerOfTenShortByOneKeepsDigits() external {
        int256 min = type(int256).min;
        int256 max = type(int256).max;
        int256 eb = min + 75;
        (int256 mc, int256 me) = this.preShortfallDiv(max, 1000, 1, eb);
        assertEq(mc, max, "baseline keeps the last digit");
        unchecked {
            assertEq(me, 1000 - 75 - min, "baseline exponent wraps");
        }
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, max, 925));
        this.liveDiv(max, 1000, 1, eb);
        checkDiv(max, 1000, 1, eb);
    }

    /// type(int256).min over a positive power of ten at the floor fits
    /// int256 off it, so the baseline sheds a digit only at the floor.
    function testPreShortfallEquivalenceDivMinByOneAtFloorSheds() external {
        int256 min = type(int256).min;
        int256 ea = 17810781030204754479236433;
        int256 eb = min + 34;
        (int256 qc, int256 qe) = this.preShortfallDiv(min, 0, 1, 0);
        assertEq(qc, min, "off the floor keeps every digit");
        assertEq(qe, 0, "off the floor exponent");
        (int256 mc, int256 me) = this.preShortfallDiv(min, ea, 1, eb);
        assertEq(mc, min / 10, "baseline sheds at the floor");
        unchecked {
            assertEq(me, 1 + ea - eb, "baseline exponent wraps");
        }
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, min, ea - 34));
        this.liveDiv(min, ea, 1, eb);
        checkDiv(min, ea, 1, eb);
    }

    /// #645: at 2b19ed13 a positive 2^255 quotient at exponent
    /// type(int256).max sheds a digit in `unabsUnsignedMulOrDivLossy`, whose
    /// checked `exponent + 1` panics. The baseline must reproduce that, not
    /// the live helper's later `UnabsExponentOverflow` (#502).
    function testPreShortfallDivShedAtExponentMaxPanics() external {
        int256 min = type(int256).min;
        int256 max = type(int256).max;
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        this.preShortfallDiv(min, max, -1e76, -76);
        checkDiv(min, max, -1e76, -76);
    }

    function testPreShortfallEquivalenceDivPacked(int224 a, int32 ea, int224 b, int32 eb) external view {
        checkDiv(a, ea, b, eb);
    }

    function checkInv(int256 c, int256 e) internal view {
        (bool mOk, bytes memory m) = run(abi.encodeCall(this.preShortfallInv, (c, e)));
        (bool pOk, bytes memory p) = run(abi.encodeCall(this.liveInv, (c, e)));
        (bool mdOk, bytes memory md) = run(abi.encodeCall(this.preShortfallDiv, (1e76, -76, c, e)));
        (bool pdOk, bytes memory pd) = run(abi.encodeCall(this.liveDiv, (1e76, -76, c, e)));
        assertTrue(mOk == mdOk && pOk == pdOk, "inv is div");
        assertEq(m, md, "baseline inv is div");
        assertEq(p, pd, "live inv is div");
        checkDiv(1e76, -76, c, e);
    }

    function testPreShortfallEquivalenceInv(int256 c, int256 e, uint8 shift) external view {
        checkInv(digits(c, shift), e);
    }

    function testPreShortfallEquivalenceInvNearFloor(int256 c, uint256 e, uint8 shift) external view {
        checkInv(digits(c, shift), nearFloor(e));
    }

    /// The live library's add or sub against the exact parts. Sub negates `b`
    /// exactly, so `-type(int256).min` is `2^255` at 77 digits.
    function checkAddSubExact(bool isSub, int256 a, int256 ea, int256 b, int256 eb, bool ok, bytes memory ret)
        internal
        pure
    {
        (bool overflows, int256 ec, int256 ee) =
            isSub ? LibExactFloat.subPartsWide(a, ea, b, eb) : LibExactFloat.addPartsWide(a, ea, b, eb);
        if (overflows) {
            assertFalse(ok, "exact add overflows");
            assertEq(selector(ret), ExponentOverflow.selector, "add ExponentOverflow");
            return;
        }
        assertTrue(ok, "exact add returns");
        (int256 c, int256 e) = pair(ret);
        assertEq(c, ec, "exact add coefficient");
        assertEq(e, ee, "exact add exponent");
    }

    function checkAddSub(bool isSub, int256 a, int256 ea, int256 b, int256 eb) internal view {
        (bool mOk, bytes memory m) = run(
            isSub
                ? abi.encodeCall(this.preShortfallSub, (a, ea, b, eb))
                : abi.encodeCall(this.preShortfallAdd, (a, ea, b, eb))
        );
        (bool pOk, bytes memory p) =
            run(isSub ? abi.encodeCall(this.liveSub, (a, ea, b, eb)) : abi.encodeCall(this.liveAdd, (a, ea, b, eb)));
        checkAddSubExact(isSub, a, ea, b, eb, pOk, p);
        if (mOk == pOk && keccak256(m) == keccak256(p)) return;
        // By design (#459, #461, #462): the baseline sheds a digit negating
        // `type(int256).min` before the sum, the live library negates it
        // exactly.
        if (isSub && b == type(int256).min) return;

        if (mOk) {
            (int256 mc, int256 me) = pair(m);
            (int256 pc, int256 pe) = pair(p);
            // By design (#495): a zero sum is the zero constants, the baseline
            // keeps an exponent.
            if (pc == 0) {
                assertEq(pe, 0, "zero exponent");
                if (mc == 0) return;
                pe = me;
            }
            if (a != 0 && b != 0 && (a < 0) != (isSub ? b > 0 : b < 0)) {
                // By design (#350): the magnitudes cancel, the baseline
                // truncates the smaller operand towards zero, so the sum one
                // unit away from zero where it sheds digits, the live library
                // the sum.
                assertEq(pe, me, "cancel exponent");
                assertEq(mc - pc, mc < 0 ? int256(-1) : int256(1), "cancel");
                return;
            }
            // By design (#394): past int256 the baseline sheds each operand's
            // last digit, the live library the sum's, one unit further from
            // zero where those digits carry.
            assertEq(pe, me, "carry exponent");
            assertEq(pc - mc, pc < 0 ? int256(-1) : int256(1), "carry");
            return;
        }

        // By design: the baseline reverts MaximizeOverflow at the floor, the
        // live library adds as if the operands were lifted off it, then sheds
        // the digits the floor cannot hold.
        assertEq(selector(m), MaximizeOverflow.selector, "baseline MaximizeOverflow");
        assertTrue(atFloor(a, ea, b, eb), "differs off the floor");
    }

    function testPreShortfallEquivalenceAdd(int256 a, int256 ea, int256 b, int256 eb, uint8 sa, uint8 sb, bool isSub)
        external
        view
    {
        checkAddSub(isSub, digits(a, sa), ea, digits(b, sb), eb);
    }

    function testPreShortfallEquivalenceAddNearFloor(
        int256 a,
        uint256 ea,
        int256 b,
        uint256 eb,
        uint8 sa,
        uint8 sb,
        int256 other,
        uint8 which,
        bool isSub
    ) external view {
        int256 expA = which % 3 == 1 ? other : nearFloor(ea);
        int256 expB = which % 3 == 2 ? other : nearFloor(eb);
        checkAddSub(isSub, digits(a, sa), expA, digits(b, sb), expB);
    }

    function testPreShortfallEquivalenceAddPacked(int224 a, int32 ea, int224 b, int32 eb, bool isSub) external view {
        checkAddSub(isSub, a, ea, b, eb);
    }

    function assertDiffers(bytes memory preShortfallCall, bytes memory liveCall) internal view {
        (bool mOk, bytes memory m) = run(preShortfallCall);
        (bool pOk, bytes memory p) = run(liveCall);
        assertFalse(mOk == pOk && keccak256(m) == keccak256(p), "differs from baseline");
    }

    function testPreShortfallEquivalenceMaximizeFloorExamples() external view {
        int256 min = type(int256).min;
        // The baseline stops at 76 digits with `full` set, the live library
        // takes the 77th.
        (int256 c, int256 e, bool full) = this.preShortfallMaximize(1e75, min);
        assertEq(c, 1e75);
        assertEq(e, min);
        assertTrue(full);
        (int256 pc, int256 pe, int256 shortfall) = this.liveMaximize(1e75, min);
        assertEq(pc, 1e76);
        assertEq(pe, min);
        assertEq(shortfall, 1);
        checkMaximize(1e75, min);
        checkMaximize(1, min + 3);
        checkMaximize(-1, min);
    }

    function testPreShortfallEquivalenceMaximizeFullFloorExamples() external view {
        int256 min = type(int256).min;
        assertDiffers(
            abi.encodeCall(this.preShortfallMaximizeFull, (1e75, min)),
            abi.encodeCall(this.liveMaximizeFull, (1e75, min))
        );
        checkMaximizeFull(1e75, min);
        checkMaximizeFull(1, min + 3);
    }

    function testPreShortfallEquivalenceDivFloorExamples() external view {
        int256 min = type(int256).min;
        int256 max = type(int256).max;
        // The baseline wraps the exponent, off the floor and at it.
        assertDiffers(
            abi.encodeCall(this.preShortfallDiv, (1, max - 3, 1, -100)),
            abi.encodeCall(this.liveDiv, (1, max - 3, 1, -100))
        );
        checkDiv(1, max - 3, 1, -100);
        assertDiffers(
            abi.encodeCall(this.preShortfallDiv, (1, 1000, 3, min)), abi.encodeCall(this.liveDiv, (1, 1000, 3, min))
        );
        checkDiv(1, 1000, 3, min);
        // #291: a ±1 divisor at the floor.
        assertDiffers(
            abi.encodeCall(this.preShortfallDiv, (1, min, 1, min)), abi.encodeCall(this.liveDiv, (1, min, 1, min))
        );
        checkDiv(1, min, 1, min);
        checkDiv(-7, min + 5, 1, min);
        assertDiffers(
            abi.encodeCall(this.preShortfallDiv, (1, 1000, -1, min)), abi.encodeCall(this.liveDiv, (1, 1000, -1, min))
        );
        checkDiv(1, 1000, -1, min);
        // #291: a power of ten divisor at the floor.
        assertDiffers(
            abi.encodeCall(this.preShortfallDiv, (3, 0, 100, min)), abi.encodeCall(this.liveDiv, (3, 0, 100, min))
        );
        checkDiv(3, 0, 100, min);
        // #292: a 76 digit numerator at the floor.
        assertDiffers(
            abi.encodeCall(this.preShortfallDiv, (1e75 + 1, min, 3, min)),
            abi.encodeCall(this.liveDiv, (1e75 + 1, min, 3, min))
        );
        checkDiv(1e75 + 1, min, 3, min);
        // #368: a positive 2^255 quotient below the floor, by each scale,
        // down to the last digit it keeps.
        for (int256 u = 1; u <= 76; u++) {
            this.checkDivMinByMinusScaleBelowFloor(u);
        }
    }

    /// One shed of the #368 loop, in its own call frame so memory does not
    /// accumulate across the 76 sheds.
    function checkDivMinByMinusScaleBelowFloor(int256 u) external view {
        int256 min = type(int256).min;
        assertDiffers(
            abi.encodeCall(this.preShortfallDiv, (min, min + 76, -1e76, u)),
            abi.encodeCall(this.liveDiv, (min, min + 76, -1e76, u))
        );
        checkDiv(min, min + 76, -1e76, u);
        checkDiv(min, min + 75, -1e75, u);
    }

    function testPreShortfallEquivalenceAddFloorExamples() external view {
        int256 min = type(int256).min;
        assertDiffers(
            abi.encodeCall(this.preShortfallAdd, (1, min, 1, min)), abi.encodeCall(this.liveAdd, (1, min, 1, min))
        );
        checkAddSub(false, 1, min, 1, min);
        checkAddSub(false, 1, min + 100, 1, min);
        checkAddSub(false, 1, type(int256).max, 1, min);
        assertDiffers(
            abi.encodeCall(this.preShortfallSub, (2, min, 1, min)), abi.encodeCall(this.liveSub, (2, min, 1, min))
        );
        checkAddSub(true, 2, min, 1, min);
        checkAddSub(true, 1, min, 1, min);
    }

    /// Hand-derived results of both, so the cancelling class is entered.
    function checkCancelExample(
        bool isSub,
        int256 a,
        int256 ea,
        int256 b,
        int256 eb,
        int256 pc,
        int256 pe,
        int256 mc,
        int256 me
    ) internal view {
        (bool mOk, bytes memory m) = run(
            isSub
                ? abi.encodeCall(this.preShortfallSub, (a, ea, b, eb))
                : abi.encodeCall(this.preShortfallAdd, (a, ea, b, eb))
        );
        (bool pOk, bytes memory p) =
            run(isSub ? abi.encodeCall(this.liveSub, (a, ea, b, eb)) : abi.encodeCall(this.liveAdd, (a, ea, b, eb)));
        assertTrue(mOk && pOk, "returns");
        assertEq(m, abi.encode(mc, me), "baseline");
        assertEq(p, abi.encode(pc, pe), "live");
        checkAddSub(isSub, a, ea, b, eb);
    }

    /// 1e76 - 1e-100: under one unit of 1e76, so the baseline keeps 1e76, a
    /// decade past the live library's 76 nines. 1e76 - (1e76 + 5)e-10: the
    /// operand aligns to 1e66 shedding 5e-10, so the baseline sums 1e76 - 1e66
    /// and the live library one less.
    function testPreShortfallEquivalenceAddCancelExamples() external view {
        checkCancelExample(false, 1e76, 0, -1, -100, 1e76 - 1, 0, 1e76, 0);
        checkCancelExample(true, -1e76, 0, -1, -100, -(1e76 - 1), 0, -1e76, 0);
        checkCancelExample(true, 1e76, 0, 1e76 + 5, -10, 1e76 - 1e66 - 1, 0, 1e76 - 1e66, 0);
        checkCancelExample(false, -1e76, 0, 1e76 + 5, -10, -(1e76 - 1e66 - 1), 0, -(1e76 - 1e66), 0);
    }
}
