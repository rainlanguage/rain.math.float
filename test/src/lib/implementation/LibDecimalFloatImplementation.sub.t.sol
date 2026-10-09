// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    LibDecimalFloatImplementation,
    EXPONENT_MAX,
    EXPONENT_MIN
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";

contract LibDecimalFloatImplementationSubTest is Test {
    /// `a - b` is `a + (-b)` rounded by the add rule, from the exact sum.
    function checkSubMatchesRule(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) internal pure {
        // -b by the representable-range rule: exact, but for int256.min, whose
        // negation 2^255 sheds a digit.
        (int256 negatedCoefficientB, int256 negatedExponentB) = LibTestExactDecimal.signedParts(
            signedCoefficientB > 0, LibTestExactDecimal.abs(signedCoefficientB), exponentB
        );
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibTestExactDecimal.addParts(signedCoefficientA, exponentA, negatedCoefficientB, negatedExponentB);
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.sub(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(signedCoefficient, expectedSignedCoefficient, "coefficient");
        assertEq(exponent, expectedExponent, "exponent");
    }

    function testSubMatchesRule(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) external pure {
        exponentA = bound(exponentA, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
        exponentB = bound(exponentB, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
        checkSubMatchesRule(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// As `testSubMatchesRule`, with the operands' digits overlapping or
    /// adjacent.
    function testSubMatchesRuleNearby(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 gap
    ) external pure {
        exponentA = bound(exponentA, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
        checkSubMatchesRule(signedCoefficientA, exponentA, signedCoefficientB, exponentA + bound(gap, -80, 80));
    }

    /// As `testSubMatchesRuleNearby`, with `b` int256.min.
    function testSubMinSignedValue(int256 signedCoefficientA, int256 exponentA, int256 gap) external pure {
        exponentA = bound(exponentA, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
        checkSubMatchesRule(signedCoefficientA, exponentA, type(int256).min, exponentA + bound(gap, -80, 80));
    }

    /// As `testSubMatchesRuleNearby`, with `a` within two of `b`'s leading
    /// digits, so that the difference cancels down to `b`'s trailing digits.
    function testSubMatchesRuleCancelling(int256 signedCoefficientB, int256 exponentB, uint256 gap, int256 delta)
        external
        pure
    {
        exponentB = bound(exponentB, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
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

    /// Near the floor, the difference is the difference of the same operands
    /// shifted up by `-type(int256).min`, truncated to the floor.
    function testSubNearFloorMatchesShifted(
        int256 signedCoefficientA,
        int256 signedCoefficientB,
        uint256 headroomA,
        uint256 headroomB
    ) external pure {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exponentA = int256(bound(headroomA, 0, 80));
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exponentB = int256(bound(headroomB, 0, 80));
        (int256 expectedCoefficient, int256 expectedExponent) =
            LibDecimalFloatImplementation.sub(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        if (expectedExponent < 0) {
            expectedCoefficient =
                LibDecimalFloatImplementation.withTargetExponent(expectedCoefficient, expectedExponent, 0);
            expectedExponent = 0;
        }
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.sub(
            signedCoefficientA, type(int256).min + exponentA, signedCoefficientB, type(int256).min + exponentB
        );
        assertTrue(
            LibDecimalFloatImplementation.eq(
                signedCoefficient, exponent - type(int256).min, expectedCoefficient, expectedExponent
            ),
            "shifted difference"
        );
    }
}
