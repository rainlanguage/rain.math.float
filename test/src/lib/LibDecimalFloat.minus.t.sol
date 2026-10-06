// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {Test} from "forge-std-1.17.0/src/Test.sol";

contract LibDecimalFloatMinusTest is Test {
    using LibDecimalFloat for Float;

    function minusExternal(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.minus(signedCoefficient, exponent);
    }

    function minusExternal(Float float) external pure returns (Float) {
        return LibDecimalFloat.minus(float);
    }

    /// a < b iff -a > -b for all non-equal packed floats.
    function testNegationReversesOrder(Float a, Float b) external pure {
        vm.assume(!a.eq(b));
        bool aLtB = a.lt(b);
        bool negAGtNegB = a.minus().gt(b.minus());
        assertTrue(aLtB == negAGtNegB, "negation should reverse ordering");
    }

    function testMinusPacked(Float float) external {
        (int256 signedCoefficientFloat, int256 exponentFloat) = float.unpack();
        try this.minusExternal(signedCoefficientFloat, exponentFloat) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            // Negating int224.min leaves int224, so the packed result is the
            // packing of the unpacked one, not the unpacked one itself.
            (Float expected,) = LibDecimalFloat.packLossy(signedCoefficient, exponent);
            Float floatMinus = this.minusExternal(float);
            assertEq(Float.unwrap(expected), Float.unwrap(floatMinus));
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.minusExternal(float);
        }
    }
}
