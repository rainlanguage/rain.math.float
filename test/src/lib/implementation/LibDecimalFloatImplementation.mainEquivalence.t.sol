// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibDecimalFloatImplementationMain} from "test/lib/LibDecimalFloatImplementationMain.sol";
import {LogTest} from "../../../abstract/LogTest.sol";
import {MaximizeOverflow, ExponentOverflow, Log10Negative} from "src/error/ErrDecimalFloat.sol";

/// Wherever main returns, the PR returns the same bytes, and wherever main
/// reverts, the PR reverts the same bytes, except in the floor shortfall
/// classes each `check*` names. Those are asserted against an oracle.
contract LibDecimalFloatImplementationMainEquivalenceTest is LogTest {
    /// Lifts a floor operand clear of every maximize shift.
    int256 constant SHIFT = 200;

    function mainMaximize(int256 c, int256 e) external pure returns (int256, int256, bool) {
        return LibDecimalFloatImplementationMain.maximize(c, e);
    }

    function prMaximize(int256 c, int256 e) external pure returns (int256, int256, int256) {
        return LibDecimalFloatImplementation.maximize(c, e);
    }

    function mainMaximizeFull(int256 c, int256 e) external pure returns (int256, int256) {
        return LibDecimalFloatImplementationMain.maximizeFull(c, e);
    }

    function prMaximizeFull(int256 c, int256 e) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.maximizeFull(c, e);
    }

    function mainDiv(int256 a, int256 ea, int256 b, int256 eb) external pure returns (int256, int256) {
        return LibDecimalFloatImplementationMain.div(a, ea, b, eb);
    }

    function prDiv(int256 a, int256 ea, int256 b, int256 eb) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.div(a, ea, b, eb);
    }

    function mainAdd(int256 a, int256 ea, int256 b, int256 eb) external pure returns (int256, int256) {
        return LibDecimalFloatImplementationMain.add(a, ea, b, eb);
    }

    function prAdd(int256 a, int256 ea, int256 b, int256 eb) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.add(a, ea, b, eb);
    }

    function mainSub(int256 a, int256 ea, int256 b, int256 eb) external pure returns (int256, int256) {
        return LibDecimalFloatImplementationMain.sub(a, ea, b, eb);
    }

    function prSub(int256 a, int256 ea, int256 b, int256 eb) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.sub(a, ea, b, eb);
    }

    function mainInv(int256 c, int256 e) external pure returns (int256, int256) {
        return LibDecimalFloatImplementationMain.inv(c, e);
    }

    function prInv(int256 c, int256 e) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.inv(c, e);
    }

    function mainLog10(address tables, int256 c, int256 e) external view returns (int256, int256) {
        return LibDecimalFloatImplementationMain.log10(tables, c, e);
    }

    function prLog10(address tables, int256 c, int256 e) external view returns (int256, int256) {
        return LibDecimalFloatImplementation.log10(tables, c, e);
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
        (int256 mc, int256 me, bool full) = this.mainMaximize(c, e);
        (int256 pc, int256 pe, int256 shortfall) = this.prMaximize(c, e);
        assertEq(shortfall, slowShortfall(c, e), "shortfall");
        if (shortfall == 0) {
            assertEq(pc, mc, "coefficient");
            assertEq(pe, me, "exponent");
            assertTrue(full, "full");
            return;
        }
        // By design: main stops short of the floor, the PR fills the
        // coefficient and reports the digits the exponent could not take.
        assertEq(pe, type(int256).min, "floor");
        int256 extra = me - type(int256).min + shortfall;
        assertTrue(extra > 0 && extra <= 77, "extra digits");
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(mc * int256(10 ** uint256(extra)), pc, "same value");
    }

    function testMainEquivalenceMaximize(int256 c, int256 e, uint8 shift) external view {
        checkMaximize(digits(c, shift), e);
    }

    function testMainEquivalenceMaximizeNearFloor(int256 c, uint256 e, uint8 shift) external view {
        checkMaximize(digits(c, shift), nearFloor(e));
    }

    function testMainEquivalenceMaximizePacked(int224 c, int32 e) external view {
        checkMaximize(c, e);
    }

    function checkMaximizeFull(int256 c, int256 e) internal view {
        (bool mOk, bytes memory m) = run(abi.encodeCall(this.mainMaximizeFull, (c, e)));
        (bool pOk, bytes memory p) = run(abi.encodeCall(this.prMaximizeFull, (c, e)));
        if (slowShortfall(c, e) == 0) {
            assertTrue(mOk && pOk, "both return");
            assertEq(p, m, "same result");
            return;
        }
        // By design: any shortfall reverts, including where main returned a
        // 76 digit coefficient it stopped at the floor.
        assertFalse(pOk, "reverts");
        assertEq(p, abi.encodeWithSelector(MaximizeOverflow.selector, c, e), "revert data");
        if (!mOk) assertEq(m, p, "same revert");
    }

    function testMainEquivalenceMaximizeFull(int256 c, int256 e, uint8 shift) external view {
        checkMaximizeFull(digits(c, shift), e);
    }

    function testMainEquivalenceMaximizeFullNearFloor(int256 c, uint256 e, uint8 shift) external view {
        checkMaximizeFull(digits(c, shift), nearFloor(e));
    }

    function testMainEquivalenceMaximizeFullPacked(int224 c, int32 e) external view {
        checkMaximizeFull(c, e);
    }

    function checkDiv(int256 a, int256 ea, int256 b, int256 eb) internal view {
        (bool mOk, bytes memory m) = run(abi.encodeCall(this.mainDiv, (a, ea, b, eb)));
        (bool pOk, bytes memory p) = run(abi.encodeCall(this.prDiv, (a, ea, b, eb)));
        if (mOk == pOk && keccak256(m) == keccak256(p)) return;

        if (!pOk) {
            // By design: the quotient exponent is past type(int256).max and
            // the PR reverts, where main either wraps it or reverts
            // MaximizeOverflow on a ±1 divisor at the floor (#291).
            assertEq(selector(p), ExponentOverflow.selector, "PR overflow");
            assertTrue(ea > 0 && eb < 0, "signs");
            (int256 qc, int256 qe) = this.mainDiv(a, 0, b, 0);
            assertTrue(exponentPastMax(ea, eb, qe), "true exponent past max");
            if (mOk) {
                (int256 mc, int256 me) = pair(m);
                assertTrue(me < 0, "main wrapped");
                // #291: main drops a digit for a power of ten divisor at the
                // floor.
                if (slowShortfall(b, eb) > 0 && isPowerOfTen(b)) {
                    qc /= 10;
                    qe += 1;
                }
                unchecked {
                    assertTrue(
                        LibDecimalFloatImplementation.eq(mc, me - ea + eb, qc, qe), "main is the quotient mod 2^256"
                    );
                }
            } else {
                assertEq(selector(m), MaximizeOverflow.selector, "main MaximizeOverflow");
                assertTrue(b == 1 || b == -1, "divisor is one");
                assertTrue(slowShortfall(b, eb) > 0, "divisor at the floor");
            }
            return;
        }

        // By design: main reverts or keeps fewer digits (#291, #292), the PR
        // matches main on the same operands lifted off the floor.
        assertTrue(atFloor(a, ea, b, eb), "differs off the floor");
        assertTrue(ea <= type(int256).max - SHIFT && eb <= type(int256).max - SHIFT, "liftable");
        (bool sOk, bytes memory s) = run(abi.encodeCall(this.mainDiv, (a, ea + SHIFT, b, eb + SHIFT)));
        assertTrue(sOk, "lifted main returns");
        assertEq(p, s, "PR matches lifted main");
    }

    function testMainEquivalenceDiv(int256 a, int256 ea, int256 b, int256 eb, uint8 sa, uint8 sb) external view {
        checkDiv(digits(a, sa), ea, digits(b, sb), eb);
    }

    function testMainEquivalenceDivNearFloor(
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

    function testMainEquivalenceDivPacked(int224 a, int32 ea, int224 b, int32 eb) external view {
        checkDiv(a, ea, b, eb);
    }

    function checkInv(int256 c, int256 e) internal view {
        (bool mOk, bytes memory m) = run(abi.encodeCall(this.mainInv, (c, e)));
        (bool pOk, bytes memory p) = run(abi.encodeCall(this.prInv, (c, e)));
        (bool mdOk, bytes memory md) = run(abi.encodeCall(this.mainDiv, (1e76, -76, c, e)));
        (bool pdOk, bytes memory pd) = run(abi.encodeCall(this.prDiv, (1e76, -76, c, e)));
        assertTrue(mOk == mdOk && pOk == pdOk, "inv is div");
        assertEq(m, md, "main inv is div");
        assertEq(p, pd, "PR inv is div");
        checkDiv(1e76, -76, c, e);
    }

    function testMainEquivalenceInv(int256 c, int256 e, uint8 shift) external view {
        checkInv(digits(c, shift), e);
    }

    function testMainEquivalenceInvNearFloor(int256 c, uint256 e, uint8 shift) external view {
        checkInv(digits(c, shift), nearFloor(e));
    }

    function checkAddSub(bool isSub, int256 a, int256 ea, int256 b, int256 eb) internal view {
        (bool mOk, bytes memory m) =
            run(isSub ? abi.encodeCall(this.mainSub, (a, ea, b, eb)) : abi.encodeCall(this.mainAdd, (a, ea, b, eb)));
        (bool pOk, bytes memory p) =
            run(isSub ? abi.encodeCall(this.prSub, (a, ea, b, eb)) : abi.encodeCall(this.prAdd, (a, ea, b, eb)));
        if (mOk == pOk && keccak256(m) == keccak256(p)) return;

        // By design: main reverts MaximizeOverflow at the floor, the PR adds
        // as if the operands were lifted off it, then sheds the digits the
        // floor cannot hold.
        assertFalse(mOk, "main reverts");
        assertEq(selector(m), MaximizeOverflow.selector, "main MaximizeOverflow");
        assertTrue(atFloor(a, ea, b, eb), "differs off the floor");
        assertTrue(pOk, "PR returns");
        if (isSub) (b, eb) = LibDecimalFloatImplementation.minus(b, eb);
        (int256 pc, int256 pe) = pair(p);
        (int256 ec, int256 ee) = expectedAdd(a, ea, b, eb);
        assertEq(pc, ec, "coefficient");
        assertEq(pe, ee, "exponent");
    }

    function expectedAdd(int256 a, int256 ea, int256 b, int256 eb) internal view returns (int256, int256) {
        // The other operand is more than 76 digits above the floor one.
        if (ea > type(int256).max - SHIFT) return this.mainMaximizeFull(a, ea);
        if (eb > type(int256).max - SHIFT) return this.mainMaximizeFull(b, eb);
        (int256 c, int256 e) = this.mainAdd(a, ea + SHIFT, b, eb + SHIFT);
        if (e >= type(int256).min + SHIFT) return (c, e - SHIFT);
        int256 shed = type(int256).min + SHIFT - e;
        assertTrue(shed <= 76, "shed");
        // forge-lint: disable-next-line(unsafe-typecast)
        return (c / int256(10 ** uint256(shed)), type(int256).min);
    }

    function testMainEquivalenceAdd(int256 a, int256 ea, int256 b, int256 eb, uint8 sa, uint8 sb, bool isSub)
        external
        view
    {
        checkAddSub(isSub, digits(a, sa), ea, digits(b, sb), eb);
    }

    function testMainEquivalenceAddNearFloor(
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

    function testMainEquivalenceAddPacked(int224 a, int32 ea, int224 b, int32 eb, bool isSub) external view {
        checkAddSub(isSub, a, ea, b, eb);
    }

    function checkLog10(int256 c, int256 e) internal {
        address tables = logTables();
        (bool mOk, bytes memory m) = run(abi.encodeCall(this.mainLog10, (tables, c, e)));
        (bool pOk, bytes memory p) = run(abi.encodeCall(this.prLog10, (tables, c, e)));
        if (mOk == pOk && keccak256(m) == keccak256(p)) return;

        // By design: main reverts MaximizeOverflow at the floor before it
        // checks the sign.
        assertFalse(mOk, "main reverts");
        assertEq(selector(m), MaximizeOverflow.selector, "main MaximizeOverflow");
        int256 shortfall = slowShortfall(c, e);
        assertTrue(shortfall > 0, "differs off the floor");
        if (c < 0) {
            assertEq(p, abi.encodeWithSelector(Log10Negative.selector, c, e), "PR Log10Negative");
            return;
        }

        // log10(c * 10^e) = log10(full * 10^min) - shortfall, with main
        // evaluating the right hand side.
        assertTrue(pOk, "PR returns");
        (int256 full,) = slowMaximize(c);
        (int256 lc, int256 le) = this.mainLog10(tables, full, type(int256).min);
        if (full == 1e76) {
            lc -= shortfall;
        } else {
            (lc, le) = LibDecimalFloatImplementation.minus(lc, le);
            (lc, le) = this.mainAdd(lc, le, shortfall, 0);
            (lc, le) = LibDecimalFloatImplementation.minus(lc, le);
        }
        (int256 pc, int256 pe) = pair(p);
        assertEq(pc, lc, "coefficient");
        assertEq(pe, le, "exponent");
    }

    function testMainEquivalenceLog10(int256 c, int256 e, uint8 shift) external {
        checkLog10(digits(c, shift), e);
    }

    function testMainEquivalenceLog10NearFloor(int256 c, uint256 e, uint8 shift) external {
        checkLog10(digits(c, shift), nearFloor(e));
    }

    function testMainEquivalenceLog10Packed(int224 c, int32 e) external {
        checkLog10(c, e);
    }

    function assertDiffers(bytes memory mainCall, bytes memory prCall) internal view {
        (bool mOk, bytes memory m) = run(mainCall);
        (bool pOk, bytes memory p) = run(prCall);
        assertFalse(mOk == pOk && keccak256(m) == keccak256(p), "differs from main");
    }

    function testMainEquivalenceMaximizeFloorExamples() external view {
        int256 min = type(int256).min;
        // Main stops at 76 digits with `full` set, the PR takes the 77th.
        (int256 c, int256 e, bool full) = this.mainMaximize(1e75, min);
        assertEq(c, 1e75);
        assertEq(e, min);
        assertTrue(full);
        (int256 pc, int256 pe, int256 shortfall) = this.prMaximize(1e75, min);
        assertEq(pc, 1e76);
        assertEq(pe, min);
        assertEq(shortfall, 1);
        checkMaximize(1e75, min);
        checkMaximize(1, min + 3);
        checkMaximize(-1, min);
    }

    function testMainEquivalenceMaximizeFullFloorExamples() external view {
        int256 min = type(int256).min;
        assertDiffers(
            abi.encodeCall(this.mainMaximizeFull, (1e75, min)), abi.encodeCall(this.prMaximizeFull, (1e75, min))
        );
        checkMaximizeFull(1e75, min);
        checkMaximizeFull(1, min + 3);
    }

    function testMainEquivalenceDivFloorExamples() external view {
        int256 min = type(int256).min;
        int256 max = type(int256).max;
        // Main wraps the exponent, off the floor and at it.
        assertDiffers(
            abi.encodeCall(this.mainDiv, (1, max - 3, 1, -100)), abi.encodeCall(this.prDiv, (1, max - 3, 1, -100))
        );
        checkDiv(1, max - 3, 1, -100);
        assertDiffers(abi.encodeCall(this.mainDiv, (1, 1000, 3, min)), abi.encodeCall(this.prDiv, (1, 1000, 3, min)));
        checkDiv(1, 1000, 3, min);
        // #291: a ±1 divisor at the floor.
        assertDiffers(abi.encodeCall(this.mainDiv, (1, min, 1, min)), abi.encodeCall(this.prDiv, (1, min, 1, min)));
        checkDiv(1, min, 1, min);
        checkDiv(-7, min + 5, 1, min);
        assertDiffers(abi.encodeCall(this.mainDiv, (1, 1000, -1, min)), abi.encodeCall(this.prDiv, (1, 1000, -1, min)));
        checkDiv(1, 1000, -1, min);
        // #291: a power of ten divisor at the floor.
        assertDiffers(abi.encodeCall(this.mainDiv, (3, 0, 100, min)), abi.encodeCall(this.prDiv, (3, 0, 100, min)));
        checkDiv(3, 0, 100, min);
        // #292: a 76 digit numerator at the floor.
        assertDiffers(
            abi.encodeCall(this.mainDiv, (1e75 + 1, min, 3, min)), abi.encodeCall(this.prDiv, (1e75 + 1, min, 3, min))
        );
        checkDiv(1e75 + 1, min, 3, min);
    }

    function testMainEquivalenceAddFloorExamples() external view {
        int256 min = type(int256).min;
        assertDiffers(abi.encodeCall(this.mainAdd, (1, min, 1, min)), abi.encodeCall(this.prAdd, (1, min, 1, min)));
        checkAddSub(false, 1, min, 1, min);
        checkAddSub(false, 1, min + 100, 1, min);
        checkAddSub(false, 1, type(int256).max, 1, min);
        assertDiffers(abi.encodeCall(this.mainSub, (2, min, 1, min)), abi.encodeCall(this.prSub, (2, min, 1, min)));
        checkAddSub(true, 2, min, 1, min);
        checkAddSub(true, 1, min, 1, min);
    }

    function testMainEquivalenceLog10FloorExamples() external {
        int256 min = type(int256).min;
        address tables = logTables();
        assertDiffers(
            abi.encodeCall(this.mainLog10, (tables, 1, min + 10)), abi.encodeCall(this.prLog10, (tables, 1, min + 10))
        );
        checkLog10(1, min + 10);
        assertDiffers(
            abi.encodeCall(this.mainLog10, (tables, 7, min + 10)), abi.encodeCall(this.prLog10, (tables, 7, min + 10))
        );
        checkLog10(7, min + 10);
        assertDiffers(
            abi.encodeCall(this.mainLog10, (tables, -1, min)), abi.encodeCall(this.prLog10, (tables, -1, min))
        );
        checkLog10(-1, min);
    }
}
