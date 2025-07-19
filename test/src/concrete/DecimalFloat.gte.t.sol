// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

contract DecimalFloatGteTest is Test {
    using LibDecimalFloat for Float;

    function gteExternal(Float a, Float b) external pure returns (bool) {
        return a.gte(b);
    }

    function testGteDeployed(Float a, Float b) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.gteExternal(a, b) returns (bool c) {
            bool deployedC = deployed.gte(a, b);

            assertEq(c, deployedC);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.gte(a, b);
        }
    }
}
