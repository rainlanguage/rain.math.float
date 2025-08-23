// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

contract DecimalFloatSubTest is Test {
    using LibDecimalFloat for Float;

    function subExternal(Float a, Float b) external pure returns (Float) {
        return a.sub(b);
    }

    function testSubDeployed(Float a, Float b) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.subExternal(a, b) returns (Float c) {
            Float deployedC = deployed.sub(a, b);

            assertEq(Float.unwrap(c), Float.unwrap(deployedC));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.sub(a, b);
        }
    }
}
