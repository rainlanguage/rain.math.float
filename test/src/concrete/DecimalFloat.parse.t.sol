// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibParseDecimalFloat} from "src/lib/parse/LibParseDecimalFloat.sol";

contract DecimalFloatParseTest is Test {
    using LibDecimalFloat for Float;

    function parseExternal(string memory str) external pure returns (bytes4, Float) {
        return LibParseDecimalFloat.parseDecimalFloat(str);
    }

    function testParseDeployed(string memory str) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.parseExternal(str) returns (bytes4 errorSelector, Float parsed) {
            (bytes4 deployedErrorSelector, Float deployedParsed) = deployed.parse(str);

            assertEq(errorSelector, deployedErrorSelector);
            assertEq(Float.unwrap(parsed), Float.unwrap(deployedParsed));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.parse(str);
        }
    }
}
