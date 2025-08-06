// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LogTest} from "test/abstract/LogTest.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

contract DecimalFloatSqrtTest is LogTest {
    using LibDecimalFloat for Float;

    function sqrtExternal(Float a) external view returns (Float) {
        return a.sqrt(LibDecimalFloat.LOG_TABLES_ADDRESS);
    }

    function testSqrtDeployed(Float a) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.sqrtExternal(a) returns (Float c) {
            Float deployedC = deployed.sqrt(a);

            assertEq(Float.unwrap(c), Float.unwrap(deployedC));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.sqrt(a);
        }
    }
}
