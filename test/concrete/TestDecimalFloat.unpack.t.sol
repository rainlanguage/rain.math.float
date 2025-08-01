// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {TestDecimalFloat} from "./TestDecimalFloat.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

contract TestDecimalFloatUnpackTest is Test {
    using LibDecimalFloat for Float;

    function unpackExternal(Float packed) external pure returns (int256 signedCoefficient, int256 exponent) {
        return LibDecimalFloat.unpack(packed);
    }

    function testUnpackDeployed(Float packed) external {
        TestDecimalFloat deployed = new TestDecimalFloat();

        try this.unpackExternal(packed) returns (int256 signedCoefficient, int256 exponent) {
            (int256 deployedSignedCoefficient, int256 deployedExponent) = deployed.unpack(packed);

            assertEq(signedCoefficient, deployedSignedCoefficient);
            assertEq(exponent, deployedExponent);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.unpack(packed);
        }
    }
}
