// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

contract DecimalFloatDivTest is Test {
    using LibDecimalFloat for Float;

    function divExternal(Float a, Float b) external pure returns (Float) {
        return a.div(b);
    }

    function testDivDeployed(Float a, Float b) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.divExternal(a, b) returns (Float c) {
            Float deployedC = deployed.div(a, b);

            assertEq(Float.unwrap(c), Float.unwrap(deployedC));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.div(a, b);
        }
    }
}
