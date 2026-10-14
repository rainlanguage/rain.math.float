// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "../../../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibExactFloat} from "../../../lib/LibExactFloat.sol";
import {LibTestRegion} from "../../../lib/LibTestRegion.sol";
import {ExponentOverflow} from "../../../../src/error/ErrDecimalFloat.sol";

contract LibDecimalFloatImplementationSubTest is Test {
    function subExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (int256, int256)
    {
        return LibDecimalFloatImplementation.sub(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// `a - b` is the exact difference rounded once as `add` rounds a sum, for
    /// any int256 parts: `-b` is exact at `b`'s int256 unit, so
    /// `-type(int256).min` is `2^255` at 77 digits. Past int256 at
    /// `type(int256).max` is `ExponentOverflow`.
    function checkSubMatchesRule(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) internal view {
        (bool overflows, int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibExactFloat.subPartsWide(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        try this.subExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            assertFalse(overflows, "exact difference overflows");
            assertEq(signedCoefficient, expectedSignedCoefficient, "coefficient");
            assertEq(exponent, expectedExponent, "exponent");
        } catch (bytes memory err) {
            assertTrue(overflows, "exact difference returns");
            // forge-lint: disable-next-line(unsafe-typecast)
            assertEq(bytes4(err), ExponentOverflow.selector, "ExponentOverflow");
        }
    }

    function testSubMatchesRule(int256 a, int256 ea, int256 b, int256 eb, uint8 sa, uint8 sb) external view {
        checkSubMatchesRule(LibTestRegion.anyDigits(a, sa), ea, LibTestRegion.anyDigits(b, sb), eb);
    }

    /// As `testSubMatchesRule`, with the operands' digits overlapping or
    /// adjacent, so the difference can carry past int256.
    function testSubMatchesRuleNearby(int256 a, int256 ea, int256 b, int256 gap, uint8 sa, uint8 sb) external view {
        ea = bound(ea, type(int256).min + 80, type(int256).max - 80);
        checkSubMatchesRule(
            LibTestRegion.anyDigits(a, sa), ea, LibTestRegion.anyDigits(b, sb), ea + bound(gap, -80, 80)
        );
    }

    /// As `testSubMatchesRule`, with exponents at or near the floor, where the
    /// difference sheds what it cannot hold.
    function testSubNearFloorMatchesRule(int256 a, uint256 ea, int256 b, uint256 eb, uint8 sa, uint8 sb) external view {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exponentA = type(int256).min + int256(bound(ea, 0, 160));
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exponentB = type(int256).min + int256(bound(eb, 0, 160));
        checkSubMatchesRule(LibTestRegion.anyDigits(a, sa), exponentA, LibTestRegion.anyDigits(b, sb), exponentB);
    }

    /// As `testSubMatchesRuleNearby`, with `b` int256.min.
    function testSubMinSignedValue(int256 a, int256 ea, int256 gap, uint8 sa) external view {
        ea = bound(ea, type(int256).min + 80, type(int256).max - 80);
        checkSubMatchesRule(LibTestRegion.anyDigits(a, sa), ea, type(int256).min, ea + bound(gap, -80, 80));
    }

    /// `b` int256.min at the extreme exponents.
    function testSubMinSignedValueExtremes(int256 a, int256 ea) external view {
        checkSubMatchesRule(a, ea, type(int256).min, type(int256).max);
        checkSubMatchesRule(a, ea, type(int256).min, type(int256).max - 1);
        checkSubMatchesRule(a, ea, type(int256).min, type(int256).min);
        checkSubMatchesRule(type(int256).max, type(int256).max, type(int256).min, type(int256).max - 1);
        checkSubMatchesRule(type(int256).min, type(int256).max - 1, type(int256).min, type(int256).max - 1);
        checkSubMatchesRule(type(int256).min, type(int256).max, type(int256).min, type(int256).max);
        checkSubMatchesRule(-1, type(int256).max, type(int256).min, type(int256).max);
        checkSubMatchesRule(0, ea, type(int256).min, type(int256).max);
    }

    /// Both operands int256.min, at any two exponents.
    function testSubMinFromMin(int256 ea, int256 eb) external view {
        checkSubMatchesRule(type(int256).min, ea, type(int256).min, eb);
    }

    /// As `testSubMinFromMin`, with exponents within 80 of each other, where
    /// the smaller operand keeps digits.
    function testSubMinFromMinNearby(int256 ea, int256 gap) external view {
        ea = bound(ea, type(int256).min + 80, type(int256).max - 80);
        checkSubMatchesRule(type(int256).min, ea, type(int256).min, ea + bound(gap, -80, 80));
    }

    /// #459: `-1e M - (-2^255)e M` is `(2^255 - 1)e M`, int256.max at
    /// `M = type(int256).max`, so it returns exactly.
    function testSubMinAtMaxExact() external pure {
        checkSub(-1, type(int256).max, type(int256).min, type(int256).max, type(int256).max, type(int256).max);
    }

    /// #461: `3 - (-2^255)` is `2^255 + 3`, past int256, so it truncates once
    /// to `floor((2^255 + 3) / 10)` at exponent 1 (bc: `(2^255 + 3) / 10`).
    function testSubMinRoundsOnce() external pure {
        checkSub(
            3, 0, type(int256).min, 0, 5789604461865809771178549250434395392663499233282028201972879200395656481997, 1
        );
        checkSub(
            -3, 0, type(int256).min, 0, 57896044618658097711785492504343953926634992332820282019728792003956564819965, 0
        );
    }

    /// #462: `x - x` is zero for `x = type(int256).min` at any exponent, and
    /// `0 - x` past int256 at `type(int256).max` is `ExponentOverflow`.
    function testSubMinFromItself() external {
        int256 min = type(int256).min;
        int256 max = type(int256).max;
        checkSub(min, max, min, max, 0, 0);
        checkSub(min, max - 1, min, max - 1, 0, 0);
        checkSub(min, min, min, min, 0, 0);
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, min, max));
        this.subExternal(0, 0, min, max);
    }

    /// `min e d - min e 0` is `-2^255 (1 - 10^-d)` units of `10^d`, which
    /// truncates to `-(2^255 - 1 - floor(2^255 / 10^d))` (bc), and the mirror.
    function testSubMinFromMinExamples() external pure {
        int256 min = type(int256).min;
        int256 nines = 52106440156792287940606943253909558533971493099538253817755912803560908337971;
        checkSub(min, 1, min, 0, -nines, 1);
        checkSub(min, 0, min, 1, nines, 1);
        int256 d76 = 57896044618658097711785492504343953926634992332820282019728792003956564819962;
        checkSub(min, 76, min, 0, -d76, 76);
        checkSub(min, 0, min, 76, d76, 76);
        checkSub(min, 77, min, 0, -type(int256).max, 77);
        checkSub(min, 0, min, 77, type(int256).max, 77);
    }

    /// As `testSubMatchesRuleNearby`, with `a` within two of `b`'s leading
    /// digits, so that the difference cancels down to `b`'s trailing digits.
    function testSubMatchesRuleCancelling(int256 signedCoefficientB, int256 exponentB, uint256 gap, int256 delta)
        external
        view
    {
        exponentB = bound(exponentB, type(int256).min, type(int256).max - 76);
        uint256 shed = bound(gap, 0, 76);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 leading = signedCoefficientB / int256(10 ** shed);
        delta = bound(delta, -2, 2);
        vm.assume(delta >= 0 ? leading <= type(int256).max - delta : leading >= type(int256).min - delta);
        int256 signedCoefficientA = leading + delta;
        // forge-lint: disable-next-line(unsafe-typecast)
        checkSubMatchesRule(signedCoefficientA, exponentB + int256(shed), signedCoefficientB, exponentB);
    }

    function checkSub(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal pure {
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.sub(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(signedCoefficient, expectedSignedCoefficient, "LibDecimalFloatImplementation.sub coefficient");
        assertEq(exponent, expectedExponent, "LibDecimalFloatImplementation.sub exponent");
    }

    /// `(5e76 + 5) - -(5e76 + 5)` is `1e77 + 10`, exactly `(1e76 + 1)e1`.
    function testSubCarryPastInt256() external pure {
        checkSub(5e76 + 5, 0, -(5e76 + 5), 0, 1e76 + 1, 1);
    }

    function testSubOneFromMax() external pure {
        // `1` is under one unit of the maximized `type(int224).max`, so the
        // difference truncates one unit towards zero.
        checkSub(type(int224).max, type(int32).max, 1, 0, int256(type(int224).max) * 1e9 - 1, type(int32).max - 9);
    }

    function testSubSelf(int224 signedCoefficientA, int32 exponentA) external pure {
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.sub(signedCoefficientA, exponentA, signedCoefficientA, exponentA);
        (exponent);
        assertEq(signedCoefficient, 0, "LibDecimalFloatImplementation.sub self coefficient");
    }

    /// Operands too close to `type(int256).min` to take their full shift
    /// subtract exactly when the difference fits at the floor.
    function testSubAtFloor() external pure {
        int256 min = type(int256).min;
        checkSub(1, min, -1, min, 2, min);
        checkSub(1, min, 1, min, 0, 0);
        checkSub(1, min + 1, 1, min, 9, min);
        checkSub(1, min, 1, min + 76, 1 - 1e76, min);
    }

    /// Near the floor, the difference is the exact difference rounded as
    /// `add` states it, with the digits below `10^type(int256).min` truncated
    /// towards zero.
    function testSubNearFloorExact(
        int256 signedCoefficientA,
        int256 signedCoefficientB,
        uint256 headroomA,
        uint256 headroomB
    ) external pure {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exponentA = type(int256).min + int256(bound(headroomA, 0, 80));
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exponentB = type(int256).min + int256(bound(headroomB, 0, 80));
        (bool overflowed, int256 expectedCoefficient, int256 expectedExponent) =
            LibExactFloat.subPartsWide(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertFalse(overflowed, "exact difference overflows");
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.sub(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(signedCoefficient, expectedCoefficient, "exact coefficient");
        assertEq(exponent, expectedExponent, "exact exponent");
    }
}
