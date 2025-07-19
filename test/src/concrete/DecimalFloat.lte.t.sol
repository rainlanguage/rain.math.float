// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

contract DecimalFloatLteTest is Test {
    using LibDecimalFloat for Float;

    function lteExternal(Float a, Float b) external pure returns (bool) {
        return a.lte(b);
    }

    function testLteDeployed(Float a, Float b) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.lteExternal(a, b) returns (bool c) {
            bool deployedC = deployed.lte(a, b);

            assertEq(c, deployedC);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.lte(a, b);
        }
    }
}
