// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

contract LibDecimalFloatAbsTest is Test {
    using LibDecimalFloat for Float;

    function absExternal(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloat.abs(signedCoefficient, exponent);
    }

    function absExternal(Float memory float) external pure returns (Float memory) {
        return LibDecimalFloat.abs(float);
    }
    /// Validate that operations using stack-based parameters (int256, int256)
    /// and memory-based parameters (Float struct) yield identical results.

    function testAbsMem(Float memory float) external {
        try this.absExternal(float.signedCoefficient, float.exponent) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            Float memory floatAbs = this.absExternal(float);
            assertEq(signedCoefficient, floatAbs.signedCoefficient);
            assertEq(exponent, floatAbs.exponent);
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
