// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";
import {LibFormatDecimalFloat} from "src/lib/format/LibFormatDecimalFloat.sol";

contract DecimalFloatFormatTest is Test {
    using LibDecimalFloat for Float;

    function formatExternal(Float a) external pure returns (string memory) {
        return LibFormatDecimalFloat.toDecimalString(a);
    }

    function testFormatDeployed(Float a) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.formatExternal(a) returns (string memory str) {
            string memory deployedStr = deployed.format(a);

            assertEq(str, deployedStr);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.format(a);
        }
    }
}
