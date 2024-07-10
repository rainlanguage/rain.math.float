// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, EXPONENT_MIN, EXPONENT_MAX} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatSubTest is Test {
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
            LibDecimalFloat.sub(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibDecimalFloat.add(signedCoefficientA, exponentA, -signedCoefficientB, exponentB);
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
            LibDecimalFloat.sub(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        // Which behaves the same as normalizing then adding its negation.
        (signedCoefficientB, exponentB) = LibDecimalFloatImplementation.normalize(signedCoefficientB, exponentB);
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibDecimalFloat.add(signedCoefficientA, exponentA, -signedCoefficientB, exponentB);

        assertEq(signedCoefficient, expectedSignedCoefficient);
        assertEq(exponent, expectedExponent);
    }
}
