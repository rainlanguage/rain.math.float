// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

contract DecimalFloatIsZeroTest is Test {
    using LibDecimalFloat for Float;

    function isZeroExternal(Float a) external pure returns (bool) {
        return a.isZero();
    }

    function testIsZeroDeployed(Float a) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.isZeroExternal(a) returns (bool b) {
            bool deployedB = deployed.isZero(a);

            assertEq(b, deployedB);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.isZero(a);
        }
    }
}
