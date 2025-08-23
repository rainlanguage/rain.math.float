// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

contract DecimalFloatEqTest is Test {
    using LibDecimalFloat for Float;

    function eqExternal(Float a, Float b) external pure returns (bool) {
        return a.eq(b);
    }

    function testEqDeployed(Float a, Float b) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.eqExternal(a, b) returns (bool c) {
            bool deployedC = deployed.eq(a, b);

            assertEq(c, deployedC);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.eq(a, b);
        }
    }
}
