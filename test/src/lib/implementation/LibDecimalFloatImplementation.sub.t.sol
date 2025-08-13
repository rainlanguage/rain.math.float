// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
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
}
