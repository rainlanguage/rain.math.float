// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LogTest} from "test/abstract/LogTest.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

contract DecimalFloatLog10Test is LogTest {
    using LibDecimalFloat for Float;

    function log10External(Float a) external returns (Float) {
        return a.log10(logTables());
    }

    // function testLog10Deployed(Float a) external {
    //     DecimalFloat deployed = new DecimalFloat();

    //     try this.log10External(a) returns (Float b) {
    //         Float deployedB = deployed.log10(a);

    //         assertEq(Float.unwrap(b), Float.unwrap(deployedB));
    //     } catch (bytes memory err) {
    //         vm.expectRevert(err);
    //         deployed.log10(a);
    //     }
    // }
}
