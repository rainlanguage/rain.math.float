// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

contract DecimalFloatFromFixedDecimalLossyTest is Test {
    using LibDecimalFloat for Float;

    function fromFixedDecimalLossyExternal(uint256 fixedDecimal, uint8 decimals) external pure returns (Float, bool) {
        return LibDecimalFloat.fromFixedDecimalLossyPacked(fixedDecimal, decimals);
    }

    function testFromFixedDecimalLossyDeployed(uint256 fixedDecimal, uint8 decimals) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.fromFixedDecimalLossyExternal(fixedDecimal, decimals) returns (Float packed, bool lossless) {
            (Float deployedPacked, bool deployedLossless) = deployed.fromFixedDecimalLossy(fixedDecimal, decimals);

            assertEq(Float.unwrap(packed), Float.unwrap(deployedPacked));
            assertEq(lossless, deployedLossless);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.fromFixedDecimalLossy(fixedDecimal, decimals);
        }
    }
}
