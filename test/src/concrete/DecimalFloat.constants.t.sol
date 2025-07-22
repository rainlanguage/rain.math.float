// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

contract DecimalFloatConstantsTest is Test {
    using LibDecimalFloat for Float;

    function maxValueExternal() external pure returns (Float) {
        return LibDecimalFloat.FLOAT_MAX_VALUE;
    }

    function testMaxValueDeployed() external {
        DecimalFloat deployed = new DecimalFloat();

        try this.maxValueExternal() returns (Float maxValue) {
            Float deployedMaxValue = deployed.maxValue();

            assertEq(Float.unwrap(maxValue), Float.unwrap(deployedMaxValue));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.maxValue();
        }
    }

    function eExternal() external pure returns (Float) {
        return LibDecimalFloat.FLOAT_E;
    }

    function testEDeployed() external {
        DecimalFloat deployed = new DecimalFloat();

        try this.eExternal() returns (Float eValue) {
            Float deployedEValue = deployed.e();

            assertEq(Float.unwrap(eValue), Float.unwrap(deployedEValue));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.e();
        }
    }
}