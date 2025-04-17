// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float, EXPONENT_MIN, EXPONENT_MAX} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatMinusTest is Test {
    using LibDecimalFloat for Float;

    function minusExternal(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloat.minus(signedCoefficient, exponent);
    }

    function minusExternal(Float float) external pure returns (Float) {
        return LibDecimalFloat.minus(float);
    }
    /// Stack and mem are the same.

    function testMinusMem(Float float) external {
        (int256 signedCoefficientFloat, int256 exponentFloat) = float.unpack();
        try this.minusExternal(signedCoefficientFloat, exponentFloat) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            Float floatMinus = this.minusExternal(float);
            (int256 signedCoefficientMinus, int256 exponentMinus) = floatMinus.unpack();
            assertEq(signedCoefficient, signedCoefficientMinus);
            assertEq(exponent, exponentMinus);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.minusExternal(float);
        }
    }

    /// Minus is the same as `0 - x`.
    function testMinusIsSubZero(int256 exponentZero, int256 signedCoefficient, int256 exponent) external pure {
        exponentZero = bound(exponentZero, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
        exponent = bound(exponent, EXPONENT_MIN / 10, EXPONENT_MAX / 10);

        (int256 signedCoefficientMinus, int256 exponentMinus) = LibDecimalFloat.minus(signedCoefficient, exponent);
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibDecimalFloat.sub(0, exponentZero, signedCoefficient, exponent);

        assertEq(signedCoefficientMinus, expectedSignedCoefficient);
        assertEq(exponentMinus, expectedExponent);
    }
}
