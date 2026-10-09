// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";
import {
    LibDecimalFloatImplementation,
    EXPONENT_MAX,
    EXPONENT_MIN
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

contract LibDecimalFloatImplementationSubTest is Test {
    /// Sub is the same as add, but with the second coefficient negated.
    function testSubIsAdd(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
    {
        exponentA = bound(exponentA, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
        exponentB = bound(exponentB, EXPONENT_MIN / 10, EXPONENT_MAX / 10);

        // The min signed value cannot be negated directly so we can't test it
        // in this function.
        vm.assume(signedCoefficientB != type(int256).min);

        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.sub(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibDecimalFloatImplementation.add(signedCoefficientA, exponentA, -signedCoefficientB, exponentB);
        assertEq(signedCoefficient, expectedSignedCoefficient);
        assertEq(exponent, expectedExponent);
    }

    /// We can sub the min signed value as it will be normalized.
    function testSubMinSignedValue(int256 signedCoefficientA, int256 exponentA, int256 exponentB) external pure {
        exponentA = bound(exponentA, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
        exponentB = bound(exponentB, EXPONENT_MIN / 10, EXPONENT_MAX / 10);

        // Able to sub the non-normalized min signed value.
        int256 signedCoefficientB = type(int256).min;
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.sub(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        // Minus will just shift the max min value one exponent internally.
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibDecimalFloatImplementation.add(signedCoefficientA, exponentA, -(signedCoefficientB / 10), exponentB + 1);

        assertEq(signedCoefficient, expectedSignedCoefficient);
        assertEq(exponent, expectedExponent);
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
