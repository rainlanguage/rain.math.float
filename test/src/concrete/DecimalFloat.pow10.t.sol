// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";
import {LogTest} from "test/abstract/LogTest.sol";

contract DecimalFloatPow10Test is LogTest {
    using LibDecimalFloat for Float;

    function pow10External(Float a) external returns (Float) {
        return a.pow10(logTables());
    }

    // function testPow10Deployed(Float a) external {
    //     DecimalFloat deployed = new DecimalFloat();

    //     try this.pow10External(a) returns (Float b) {
    //         Float deployedB = deployed.pow10(a);

    //         assertEq(Float.unwrap(b), Float.unwrap(deployedB));
    //     } catch (bytes memory err) {
    //         vm.expectRevert(err);
    //         deployed.pow10(a);
    //     }
    // }
}
