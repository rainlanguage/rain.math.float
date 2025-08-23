// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

contract DecimalFloatLtTest is Test {
    using LibDecimalFloat for Float;

    function ltExternal(Float a, Float b) external pure returns (bool) {
        return a.lt(b);
    }

    function testLtDeployed(Float a, Float b) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.ltExternal(a, b) returns (bool c) {
            bool deployedC = deployed.lt(a, b);

            assertEq(c, deployedC);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.lt(a, b);
        }
    }
}
