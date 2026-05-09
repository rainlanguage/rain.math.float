// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LogTest} from "test/abstract/LogTest.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

contract DecimalFloatFloorTest is LogTest {
    using LibDecimalFloat for Float;

    function floorExternal(Float a) external pure returns (Float) {
        return a.floor();
    }

    function testFloorDeployed(Float a) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.floorExternal(a) returns (Float b) {
            Float deployedB = deployed.floor(a);

            assertEq(Float.unwrap(b), Float.unwrap(deployedB));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.floor(a);
        }
    }
}
