// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

contract DecimalFloatFracTest is Test {
    using LibDecimalFloat for Float;

    function fracExternal(Float a) external pure returns (Float) {
        return a.frac();
    }

    function testFracDeployed(Float a) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.fracExternal(a) returns (Float b) {
            Float deployedB = deployed.frac(a);

            assertEq(Float.unwrap(b), Float.unwrap(deployedB));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.frac(a);
        }
    }
}
