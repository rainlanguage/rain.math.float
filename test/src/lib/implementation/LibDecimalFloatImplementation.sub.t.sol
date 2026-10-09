// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";
import {ExponentOverflow} from "src/error/ErrDecimalFloat.sol";

contract LibDecimalFloatImplementationSubTest is Test {
    function subExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (int256, int256)
    {
        return LibDecimalFloatImplementation.sub(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// `a - b` is `add(a, -b)` from the exact sum, for any int256 parts. `-b`
    /// is exact but for int256.min, whose negation 2^255 is no int256 and
    /// sheds a digit to `(2^255 / 10, e + 1)`, which is past int256 at
    /// `e = type(int256).max`. Past int256 is `ExponentOverflow`.
    function checkSubMatchesRule(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) internal view {
        if (signedCoefficientB == type(int256).min && exponentB == type(int256).max) {
            try this.subExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB) {
                revert("-int256.min at int256.max returns");
            } catch (bytes memory err) {
                assertEq(err, abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficientB, exponentB));
            }
            return;
        }
        (int256 negatedCoefficientB, int256 negatedExponentB) = LibTestExactDecimal.signedParts(
            signedCoefficientB > 0, LibTestExactDecimal.abs(signedCoefficientB), exponentB
        );
        (bool overflows, int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibTestExactDecimal.addPartsWide(signedCoefficientA, exponentA, negatedCoefficientB, negatedExponentB);
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

    /// `c` with its last `shift % 78` digits dropped.
    function dropDigits(int256 c, uint8 shift) internal pure returns (int256) {
        return c / int256(10 ** (uint256(shift) % 78));
    }

    function testSubMatchesRule(int256 a, int256 ea, int256 b, int256 eb, uint8 sa, uint8 sb) external view {
        checkSubMatchesRule(dropDigits(a, sa), ea, dropDigits(b, sb), eb);
    }

    /// As `testSubMatchesRule`, with the operands' digits overlapping or
    /// adjacent, so the difference can carry past int256.
    function testSubMatchesRuleNearby(int256 a, int256 ea, int256 b, int256 gap, uint8 sa, uint8 sb) external view {
        ea = bound(ea, type(int256).min + 80, type(int256).max - 80);
        checkSubMatchesRule(dropDigits(a, sa), ea, dropDigits(b, sb), ea + bound(gap, -80, 80));
    }

    /// As `testSubMatchesRule`, with exponents at or near the floor, where the
    /// difference sheds what it cannot hold.
    function testSubNearFloorMatchesRule(int256 a, uint256 ea, int256 b, uint256 eb, uint8 sa, uint8 sb) external view {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exponentA = type(int256).min + int256(bound(ea, 0, 160));
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exponentB = type(int256).min + int256(bound(eb, 0, 160));
        checkSubMatchesRule(dropDigits(a, sa), exponentA, dropDigits(b, sb), exponentB);
    }

    /// As `testSubMatchesRuleNearby`, with `b` int256.min.
    function testSubMinSignedValue(int256 a, int256 ea, int256 gap, uint8 sa) external view {
        ea = bound(ea, type(int256).min + 80, type(int256).max - 80);
        checkSubMatchesRule(dropDigits(a, sa), ea, type(int256).min, ea + bound(gap, -80, 80));
    }

    /// `b` int256.min at the extreme exponents.
    function testSubMinSignedValueExtremes(int256 a, int256 ea) external view {
        checkSubMatchesRule(a, ea, type(int256).min, type(int256).max);
        checkSubMatchesRule(a, ea, type(int256).min, type(int256).max - 1);
        checkSubMatchesRule(a, ea, type(int256).min, type(int256).min);
        checkSubMatchesRule(type(int256).max, type(int256).max, type(int256).min, type(int256).max - 1);
        checkSubMatchesRule(type(int256).min, type(int256).max - 1, type(int256).min, type(int256).max - 1);
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
        checkSub(type(int224).max, type(int32).max, 1, 0, int256(type(int224).max) * 1e9, type(int32).max - 9);
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
        checkSub(1, min, 1, min, 0, min);
        checkSub(1, min + 1, 1, min, 9, min);
        checkSub(1, min, 1, min + 76, 1 - 1e76, min);
    }

    /// Near the floor, the difference is the exact sum with the negated
    /// subtrahend, rounded as `add` states it, with the digits below
    /// `10^type(int256).min` truncated towards zero. Negating
    /// `type(int256).min` sheds a digit, as any magnitude past int256 does.
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
        (int256 negatedCoefficientB, int256 negatedExponentB) = LibTestExactDecimal.signedParts(
            signedCoefficientB > 0, LibTestExactDecimal.abs(signedCoefficientB), exponentB
        );
        (bool overflowed, int256 expectedCoefficient, int256 expectedExponent) =
            LibTestExactDecimal.addPartsWide(signedCoefficientA, exponentA, negatedCoefficientB, negatedExponentB);
        assertFalse(overflowed, "exact difference overflows");
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.sub(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(signedCoefficient, expectedCoefficient, "exact coefficient");
        assertEq(exponent, expectedExponent, "exact exponent");
    }
}
