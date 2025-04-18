// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

contract LibDecimalFloatInvTest is Test {
    using LibDecimalFloat for Float;

    function invExternal(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.inv(signedCoefficient, exponent);
    }

    function invExternal(Float float) external pure returns (Float) {
        return LibDecimalFloat.inv(float);
    }
    /// Stack and mem are the same.

    function testInvMem(Float float) external {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        try this.invExternal(signedCoefficient, exponent) returns (
            int256 signedCoefficientResult, int256 exponentResult
        ) {
            Float floatInv = this.invExternal(float);
            (int256 signedCoefficientResultUnpacked, int256 exponentResultUnpacked) = floatInv.unpack();
            assertEq(signedCoefficientResultUnpacked, signedCoefficientResult);
            assertEq(exponentResultUnpacked, exponentResult);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.invExternal(float);
        }
    }
}
