// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float, EXPONENT_MAX} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatMinusTest is Test {
    using LibDecimalFloat for Float;

    function minusExternal(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloat.minus(signedCoefficient, exponent);
    }

    function minusExternal(Float memory float) external pure returns (Float memory) {
        return LibDecimalFloat.minus(float);
    }
    /// Stack and mem are the same.

    function testMinusMem(Float memory float) external {
        try this.minusExternal(float.signedCoefficient, float.exponent) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            Float memory floatMinus = this.minusExternal(float);
            assertEq(signedCoefficient, floatMinus.signedCoefficient);
            assertEq(exponent, floatMinus.exponent);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.minusExternal(float);
        }
    }

    /// Minus is the same as `0 - x`.
    function testMinusIsSubZero(int256 exponentZero, int256 signedCoefficient, int256 exponent) external pure {
        exponentZero = bound(exponentZero, -EXPONENT_MAX / 10, EXPONENT_MAX / 10);
        exponent = bound(exponent, -EXPONENT_MAX / 10, EXPONENT_MAX / 10);

        (int256 signedCoefficientMinus, int256 exponentMinus) = LibDecimalFloat.minus(signedCoefficient, exponent);
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibDecimalFloat.sub(0, exponentZero, signedCoefficient, exponent);

        assertEq(signedCoefficientMinus, expectedSignedCoefficient);
        assertEq(exponentMinus, expectedExponent);
    }
}
