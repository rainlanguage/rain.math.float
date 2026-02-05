// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

contract DecimalFloatIntegerTest is Test {
    using LibDecimalFloat for Float;

    function integerExternal(Float a) external pure returns (Float) {
        return a.integer();
    }

    function testIntegerDeployed(Float a) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.integerExternal(a) returns (Float b) {
            Float deployedB = deployed.integer(a);

            assertEq(Float.unwrap(b), Float.unwrap(deployedB));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.integer(a);
        }
    }
}
