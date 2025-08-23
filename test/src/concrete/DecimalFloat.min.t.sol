// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";
import {Test} from "forge-std/Test.sol";

contract DecimalFloatMinTest is Test {
    using LibDecimalFloat for Float;

    function minExternal(Float a, Float b) external pure returns (Float) {
        return a.min(b);
    }

    function testMinDeployed(Float a, Float b) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.minExternal(a, b) returns (Float c) {
            Float deployedC = deployed.min(a, b);

            assertEq(Float.unwrap(c), Float.unwrap(deployedC));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.min(a, b);
        }
    }
}
