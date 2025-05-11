// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

contract DecimalFloatAddTest is Test {
    using LibDecimalFloat for Float;

    function addExternal(Float a, Float b) external pure returns (Float) {
        return a.add(b);
    }

    function testAddDeployed(Float a, Float b) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.addExternal(a, b) returns (Float c) {
            Float deployedC = deployed.add(a, b);

            assertEq(Float.unwrap(c), Float.unwrap(deployedC));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.add(a, b);
        }
    }
}
