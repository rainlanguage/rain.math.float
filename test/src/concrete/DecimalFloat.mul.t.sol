// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

contract DecimalFloatMulTest is Test {
    using LibDecimalFloat for Float;

    function mulExternal(Float a, Float b) external pure returns (Float) {
        return a.mul(b);
    }

    function testMulDeployed(Float a, Float b) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.mulExternal(a, b) returns (Float c) {
            Float deployedC = deployed.mul(a, b);

            assertEq(Float.unwrap(c), Float.unwrap(deployedC));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.mul(a, b);
        }
    }
}
