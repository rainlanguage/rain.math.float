// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

contract DecimalFloatToFixedDecimalLosslessTest is Test {
    using LibDecimalFloat for Float;

    function toFixedDecimalLosslessExternal(Float packed, uint8 decimals) external pure returns (uint256) {
        return LibDecimalFloat.toFixedDecimalLossless(packed, decimals);
    }

    function testToFixedDecimalLosslessDeployed(Float packed, uint8 decimals) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.toFixedDecimalLosslessExternal(packed, decimals) returns (uint256 fixedDecimal) {
            uint256 deployedFixedDecimal = deployed.toFixedDecimalLossless(packed, decimals);

            assertEq(fixedDecimal, deployedFixedDecimal);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.toFixedDecimalLossless(packed, decimals);
        }
    }
}
