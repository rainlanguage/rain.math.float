// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

contract DecimalFloatGtTest is Test {
    using LibDecimalFloat for Float;

    function gtExternal(Float a, Float b) external pure returns (bool) {
        return a.gt(b);
    }

    function testGtDeployed(Float a, Float b) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.gtExternal(a, b) returns (bool c) {
            bool deployedC = deployed.gt(a, b);

            assertEq(c, deployedC);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.gt(a, b);
        }
    }
}
