// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LogTest} from "test/abstract/LogTest.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";

contract DecimalFloatCanonicalizeTest is LogTest {
    using LibDecimalFloat for Float;

    function canonicalizeExternal(Float a) external pure returns (Float) {
        return a.canonicalize();
    }

    /// The `canonicalize` method exposed on the deployed concrete contract must
    /// match the library result for any input (and revert identically if the
    /// library reverts).
    function testCanonicalizeDeployed(Float a) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.canonicalizeExternal(a) returns (Float b) {
            Float deployedB = deployed.canonicalize(a);

            assertEq(Float.unwrap(b), Float.unwrap(deployedB));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.canonicalize(a);
        }
    }
}
