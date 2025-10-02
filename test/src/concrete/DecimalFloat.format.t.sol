// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";
import {LibFormatDecimalFloat} from "src/lib/format/LibFormatDecimalFloat.sol";

contract DecimalFloatFormatTest is Test {
    using LibDecimalFloat for Float;

    function formatExternal(Float a, Float scientificMin, Float scientificMax) external pure returns (string memory) {
        return LibFormatDecimalFloat.toDecimalString(a, a.lt(scientificMin) || a.gt(scientificMax));
    }

    function testFormatDeployed(Float a, Float scientificMin, Float scientificMax) external {
        vm.assume(scientificMin.lt(scientificMax));

        DecimalFloat deployed = new DecimalFloat();

        try this.formatExternal(a, scientificMin, scientificMax) returns (string memory str) {
            string memory deployedStr = deployed.format(a, scientificMin, scientificMax);

            assertEq(str, deployedStr);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.format(a, scientificMin, scientificMax);
        }
    }

    function testFormatConstants() external {
        DecimalFloat deployed = new DecimalFloat();

        assertEq(
            Float.unwrap(deployed.FORMAT_DEFAULT_SCIENTIFIC_MIN()), Float.unwrap(LibDecimalFloat.packLossless(1, -4))
        );
        assertEq(
            Float.unwrap(deployed.FORMAT_DEFAULT_SCIENTIFIC_MAX()), Float.unwrap(LibDecimalFloat.packLossless(1, 9))
        );
    }
}
