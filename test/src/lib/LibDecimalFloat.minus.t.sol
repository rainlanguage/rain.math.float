// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float, ExponentOverflow} from "src/lib/LibDecimalFloat.sol";

import {Test} from "forge-std-1.17.0/src/Test.sol";

contract LibDecimalFloatMinusTest is Test {
    using LibDecimalFloat for Float;

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

    /// Every Float negates exactly except an int224.min coefficient, whose
    /// negation `2^223` sheds a digit to fit int224. At the exponent ceiling
    /// that shed has nowhere to go, which is the only revert.
    function testMinusPacked(Float float) external {
        (int256 signedCoefficientFloat, int256 exponentFloat) = float.unpack();
        if (signedCoefficientFloat == type(int224).min && exponentFloat == type(int32).max) {
            vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(2 ** 223), exponentFloat));
            this.minusExternal(float);
            return;
        }
        int256 expectedCoefficient = -signedCoefficientFloat;
        int256 expectedExponent = signedCoefficientFloat == 0 ? int256(0) : exponentFloat;
        if (signedCoefficientFloat == type(int224).min) {
            expectedCoefficient = int256(2 ** 223) / 10;
            expectedExponent = exponentFloat + 1;
        }
        Float floatMinus = this.minusExternal(float);
        (int256 signedCoefficientMinus, int256 exponentMinus) = floatMinus.unpack();
        assertEq(signedCoefficientMinus, expectedCoefficient);
        assertEq(exponentMinus, expectedExponent);
    }
}
