// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LogTest} from "test/abstract/LogTest.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

contract DecimalFloatPowTest is LogTest {
    using LibDecimalFloat for Float;

    function powExternal(Float a, Float b) external view returns (Float) {
        return a.pow(b, LibDecimalFloat.LOG_TABLES_ADDRESS);
    }

    function testPowDeployed(Float a, Float b) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.powExternal(a, b) returns (Float c) {
            Float deployedC = deployed.pow(a, b);

            assertEq(Float.unwrap(c), Float.unwrap(deployedC));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.pow(a, b);
        }
    }
}
