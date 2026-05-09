// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LogTest} from "test/abstract/LogTest.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

contract DecimalFloatCeilTest is LogTest {
    using LibDecimalFloat for Float;

    function ceilExternal(Float a) external pure returns (Float) {
        return a.ceil();
    }

    function testCeilDeployed(Float a) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.ceilExternal(a) returns (Float b) {
            Float deployedB = deployed.ceil(a);

            assertEq(Float.unwrap(b), Float.unwrap(deployedB));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.ceil(a);
        }
    }
}
