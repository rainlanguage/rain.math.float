// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

contract DecimalFloatFloorTest is Test {
    using LibDecimalFloat for Float;

    function floorExternal(Float a) external pure returns (Float) {
        return a.floor();
    }

    function testFloorDeployed(Float a) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.floorExternal(a) returns (Float b) {
            Float deployedB = deployed.floor(a);

            assertEq(Float.unwrap(b), Float.unwrap(deployedB));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.floor(a);
        }
    }
}
