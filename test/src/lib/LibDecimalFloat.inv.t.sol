// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibDecimalFloat, Float, EXPONENT_MIN, EXPONENT_MAX} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatSlow} from "test/lib/LibDecimalFloatSlow.sol";

contract LibDecimalFloatInvTest is Test {
    using LibDecimalFloat for Float;

    function invExternal(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloat.inv(signedCoefficient, exponent);
    }

    function invExternal(Float memory float) external pure returns (Float memory) {
        return LibDecimalFloat.inv(float);
    }
    /// Stack and mem are the same.

    function testInvMem(Float memory float) external {
        try this.invExternal(float.signedCoefficient, float.exponent) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            Float memory floatInv = this.invExternal(float);
            assertEq(signedCoefficient, floatInv.signedCoefficient);
            assertEq(exponent, floatInv.exponent);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.invExternal(float);
        }
    }

    /// Compare reference.
    function testInvReference(int256 signedCoefficient, int256 exponent) external pure {
        vm.assume(signedCoefficient != 0);
        exponent = bound(exponent, EXPONENT_MIN, EXPONENT_MAX);

        (int256 outputSignedCoefficient, int256 outputExponent) = LibDecimalFloat.inv(signedCoefficient, exponent);
        (int256 referenceSignedCoefficient, int256 referenceExponent) =
            LibDecimalFloatSlow.invSlow(signedCoefficient, exponent);

        assertEq(outputSignedCoefficient, referenceSignedCoefficient, "coefficient");
        assertEq(outputExponent, referenceExponent, "exponent");
    }

    function testInvGas0() external pure {
        (int256 outputSignedCoefficient, int256 outputExponent) = LibDecimalFloat.inv(3e37, -37);
        (outputSignedCoefficient, outputExponent);
    }

    function testInvSlowGas0() external pure {
        (int256 outputSignedCoefficient, int256 outputExponent) = LibDecimalFloatSlow.invSlow(3e37, -37);
        (outputSignedCoefficient, outputExponent);
    }
}
