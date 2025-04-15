// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float, EXPONENT_MAX} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatNormalizeTest is Test {
    using LibDecimalFloat for Float;

    function normalizeExternal(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.normalize(signedCoefficient, exponent);
    }

    function normalizeExternal(Float memory float) external pure returns (Float memory) {
        return LibDecimalFloat.normalize(float);
    }
    /// Stack and mem are the same.

    function testNormalizeMem(Float memory float) external {
        try this.normalizeExternal(float.signedCoefficient, float.exponent) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            Float memory floatNormalized = this.normalizeExternal(float);
            assertEq(signedCoefficient, floatNormalized.signedCoefficient);
            assertEq(exponent, floatNormalized.exponent);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.normalizeExternal(float);
        }
    }
}
