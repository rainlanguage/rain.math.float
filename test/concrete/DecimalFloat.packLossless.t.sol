// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {TestDecimalFloat} from "./TestDecimalFloat.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

contract DecimalFloatPackLosslessTest is Test {
    function packLosslessExternal(int224 signedCoefficient, int32 exponent) external pure returns (Float) {
        return LibDecimalFloat.packLossless(signedCoefficient, exponent);
    }

    function testPackDeployed(int224 signedCoefficient, int32 exponent) external {
        TestDecimalFloat deployed = new TestDecimalFloat();

        try this.packLosslessExternal(signedCoefficient, exponent) returns (Float packed) {
            Float deployedPacked = deployed.packLossless(signedCoefficient, exponent);

            assertEq(Float.unwrap(packed), Float.unwrap(deployedPacked));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.packLossless(signedCoefficient, exponent);
        }
    }
}
