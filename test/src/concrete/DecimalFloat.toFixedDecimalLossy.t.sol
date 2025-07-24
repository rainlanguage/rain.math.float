// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

contract DecimalFloatToFixedDecimalLossyTest is Test {
    using LibDecimalFloat for Float;

    function toFixedDecimalLossyExternal(Float packed, uint8 decimals) external pure returns (uint256, bool) {
        return LibDecimalFloat.toFixedDecimalLossy(packed, decimals);
    }

    function testToFixedDecimalLossyDeployed(Float packed, uint8 decimals) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.toFixedDecimalLossyExternal(packed, decimals) returns (uint256 fixedDecimal, bool lossless) {
            (uint256 deployedFixedDecimal, bool deployedLossless) = deployed.toFixedDecimalLossy(packed, decimals);

            assertEq(fixedDecimal, deployedFixedDecimal);
            assertEq(lossless, deployedLossless);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.toFixedDecimalLossy(packed, decimals);
        }
    }
}
