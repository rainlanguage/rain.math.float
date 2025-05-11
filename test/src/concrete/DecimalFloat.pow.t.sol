// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LogTest} from "test/abstract/LogTest.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

contract DecimalFloatPowTest is LogTest {
    using LibDecimalFloat for Float;

    function powExternal(Float a, Float b) external returns (Float) {
        return a.pow(b, logTables());
    }

    // function testPowDeployed(Float a, Float b) external {
    //     DecimalFloat deployed = new DecimalFloat();

    //     try this.powExternal(a, b) returns (Float c) {
    //         Float deployedC = deployed.pow(a, b);

    //         assertEq(Float.unwrap(c), Float.unwrap(deployedC));
    //     } catch (bytes memory err) {
    //         vm.expectRevert(err);
    //         deployed.pow(a, b);
    //     }
    // }
}
