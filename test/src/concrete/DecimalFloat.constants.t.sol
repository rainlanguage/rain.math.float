// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

contract DecimalFloatConstantsTest is Test {
    using LibDecimalFloat for Float;

    function maxPositiveValueExternal() external pure returns (Float) {
        return LibDecimalFloat.FLOAT_MAX_POSITIVE_VALUE;
    }

    function testMaxPositiveValueDeployed() external {
        DecimalFloat deployed = new DecimalFloat();

        try this.maxPositiveValueExternal() returns (Float maxValue) {
            Float deployedMaxPositiveValue = deployed.maxPositiveValue();

            assertEq(Float.unwrap(maxValue), Float.unwrap(deployedMaxPositiveValue));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.maxPositiveValue();
        }
    }

    function minPositiveValueExternal() external pure returns (Float) {
        return LibDecimalFloat.FLOAT_MIN_POSITIVE_VALUE;
    }

    function testMinPositiveValueDeployed() external {
        DecimalFloat deployed = new DecimalFloat();

        try this.minPositiveValueExternal() returns (Float minValue) {
            Float deployedMinPositiveValue = deployed.minPositiveValue();

            assertEq(Float.unwrap(minValue), Float.unwrap(deployedMinPositiveValue));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.minPositiveValue();
        }
    }

    function maxNegativeValueExternal() external pure returns (Float) {
        return LibDecimalFloat.FLOAT_MAX_NEGATIVE_VALUE;
    }

    function testMaxNegativeValueDeployed() external {
        DecimalFloat deployed = new DecimalFloat();

        try this.maxNegativeValueExternal() returns (Float maxNegativeValue) {
            Float deployedMaxNegativeValue = deployed.maxNegativeValue();

            assertEq(Float.unwrap(maxNegativeValue), Float.unwrap(deployedMaxNegativeValue));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.maxNegativeValue();
        }
    }

    function minNegativeValueExternal() external pure returns (Float) {
        return LibDecimalFloat.FLOAT_MIN_NEGATIVE_VALUE;
    }

    function testMinNegativeValueDeployed() external {
        DecimalFloat deployed = new DecimalFloat();

        try this.minNegativeValueExternal() returns (Float minNegativeValue) {
            Float deployedMinNegativeValue = deployed.minNegativeValue();

            assertEq(Float.unwrap(minNegativeValue), Float.unwrap(deployedMinNegativeValue));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.minNegativeValue();
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
