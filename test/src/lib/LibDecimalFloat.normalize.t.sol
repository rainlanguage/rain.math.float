// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatNormalizeTest is Test {
    using LibDecimalFloat for Float;

    function normalizeExternal(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.normalize(signedCoefficient, exponent);
    }

    function normalizeExternal(Float float) external pure returns (Float) {
        return LibDecimalFloat.normalize(float);
    }
    /// Stack and mem are the same.

    function testNormalizeMem(Float float) external {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        try this.normalizeExternal(signedCoefficient, exponent) returns (
            int256 signedCoefficientNormalized, int256 exponentNormalized
        ) {
            Float floatNormalized = this.normalizeExternal(float);
            (int256 signedCoefficientUnpacked, int256 exponentUnpacked) = floatNormalized.unpack();
            assertEq(signedCoefficientNormalized, signedCoefficientUnpacked);
            assertEq(exponentNormalized, exponentUnpacked);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.normalizeExternal(float);
        }
    }
}
