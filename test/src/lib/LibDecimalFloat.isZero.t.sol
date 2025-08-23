// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatIsZeroTest is Test {
    using LibDecimalFloat for Float;

    function isZeroExternal(Float a) external pure returns (bool) {
        return a.isZero();
    }

    function testIsZeroDeployed(Float a) external {
        try this.isZeroExternal(a) returns (bool b) {
            bool deployedB = a.isZero();

            assertEq(b, deployedB);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            a.isZero();
        }
    }

    function testIsZeroEqZero(Float a) external pure {
        assertEq(a.isZero(), a.eq(Float.wrap(0)));
    }

    function testIsZeroExamples(int32 exponent) external pure {
        Float zero = Float.wrap(0);
        Float packZeroBasic = LibDecimalFloat.packLossless(0, 0);
        Float packZero = LibDecimalFloat.packLossless(0, exponent);

        assertTrue(zero.isZero());
        assertTrue(packZeroBasic.isZero());
        assertTrue(packZero.isZero());
    }

    function testNotIsZero(int224 signedCoefficient, int32 exponent) external pure {
        vm.assume(signedCoefficient != 0);
        Float notZero = LibDecimalFloat.packLossless(signedCoefficient, exponent);
        assertTrue(!notZero.isZero());
    }
}
