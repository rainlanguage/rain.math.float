// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

contract LibDecimalFloatAbsTest is Test {
    using LibDecimalFloat for Float;

    function absExternal(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloat.abs(signedCoefficient, exponent);
    }

    function absExternal(Float float) external pure returns (Float) {
        return LibDecimalFloat.abs(float);
    }

    function testAbsPacked(Float float) external {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.unpack(float);
        try this.absExternal(signedCoefficient, exponent) returns (int256 signedCoefficientAbs, int256 exponentAbs) {
            Float floatAbs = this.absExternal(float);
            assertEq(Float.unwrap(floatAbs), Float.unwrap(LibDecimalFloat.pack(signedCoefficientAbs, exponentAbs)));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.absExternal(float);
        }
    }

    /// Anything non negative is identity.
    function testAbsNonNegative(int256 signedCoefficient, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, 0, type(int256).max);
        (int256 absSignedCoefficient, int256 absExponent) = LibDecimalFloat.abs(signedCoefficient, exponent);
        assertEq(absSignedCoefficient, signedCoefficient);
        assertEq(absExponent, exponent);
    }

    /// Anything negative is negated. Except for the minimum value.
    function testAbsNegative(int256 signedCoefficient, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, type(int256).min + 1, -1);
        (int256 absSignedCoefficient, int256 absExponent) = LibDecimalFloat.abs(signedCoefficient, exponent);
        assertEq(absSignedCoefficient, -signedCoefficient);
        assertEq(absExponent, exponent);
    }

    /// Minimum value is shifted one OOM.
    function testAbsMinValue(int256 exponent) external pure {
        vm.assume(exponent < type(int256).max);
        (int256 absSignedCoefficient, int256 absExponent) = LibDecimalFloat.abs(type(int256).min, exponent);
        assertEq(absSignedCoefficient, -(type(int256).min / 10));
        assertEq(absExponent, exponent + 1);
    }
}
