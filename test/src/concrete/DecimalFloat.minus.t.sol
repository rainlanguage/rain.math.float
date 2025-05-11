// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

contract DecimalFloatMinusTest is Test {
    using LibDecimalFloat for Float;

    function minusExternal(Float a) external pure returns (Float) {
        return a.minus();
    }

    function testMinusDeployed(Float a) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.minusExternal(a) returns (Float b) {
            Float deployedB = deployed.minus(a);

            assertEq(Float.unwrap(b), Float.unwrap(deployedB));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.minus(a);
        }
    }
}
