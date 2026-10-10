// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";

contract LibDecimalFloatIsZeroTest is Test {
    using LibDecimalFloat for Float;

    function isZeroExternal(Float a) external pure returns (bool) {
        return a.isZero();
    }

    /// Never reverts, and is true exactly when the coefficient is zero,
    /// whatever the exponent bits hold.
    function testIsZeroDeployed(Float a) external view {
        bool expected = uint256(Float.unwrap(a)) & type(uint224).max == 0;
        assertEq(this.isZeroExternal(a), expected, "external");
        assertEq(a.isZero(), expected, "internal");
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
