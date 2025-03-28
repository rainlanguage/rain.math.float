// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, EXPONENT_MIN, EXPONENT_MAX, Float} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatSubTest is Test {
    using LibDecimalFloat for Float;

    function subExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (int256, int256)
    {
        return LibDecimalFloat.sub(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    function subExternal(Float memory floatA, Float memory floatB) external pure returns (Float memory) {
        return LibDecimalFloat.sub(floatA, floatB);
    }

    /// Stack and mem are the same.
    function testSubMem(Float memory a, Float memory b) external {
        try this.subExternal(a.signedCoefficient, a.exponent, b.signedCoefficient, b.exponent) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            Float memory float = this.subExternal(a, b);
            assertEq(signedCoefficient, float.signedCoefficient);
            assertEq(exponent, float.exponent);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.subExternal(a, b);
        }
    }

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

        // Minus will just shift the max min value one exponent internally.
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibDecimalFloat.add(signedCoefficientA, exponentA, -(signedCoefficientB / 10), exponentB + 1);

        assertEq(signedCoefficient, expectedSignedCoefficient);
        assertEq(exponent, expectedExponent);
    }
}
