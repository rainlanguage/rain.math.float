// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

contract DecimalFloatFromFixedDecimalLosslessTest is Test {
    using LibDecimalFloat for Float;

    function fromFixedDecimalLosslessExternal(uint256 fixedDecimal, uint8 decimals) external pure returns (Float) {
        return LibDecimalFloat.fromFixedDecimalLosslessPacked(fixedDecimal, decimals);
    }

    function testFromFixedDecimalLosslessDeployed(uint256 fixedDecimal, uint8 decimals) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.fromFixedDecimalLosslessExternal(fixedDecimal, decimals) returns (Float packed) {
            Float deployedPacked = deployed.fromFixedDecimalLossless(fixedDecimal, decimals);

            assertEq(Float.unwrap(packed), Float.unwrap(deployedPacked));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.fromFixedDecimalLossless(fixedDecimal, decimals);
        }
    }
}
