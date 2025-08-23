// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatMinusTest is Test {
    using LibDecimalFloat for Float;

    function minusExternal(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.minus(signedCoefficient, exponent);
    }

    function minusExternal(Float float) external pure returns (Float) {
        return LibDecimalFloat.minus(float);
    }

    function testMinusPacked(Float float) external {
        (int256 signedCoefficientFloat, int256 exponentFloat) = float.unpack();
        try this.minusExternal(signedCoefficientFloat, exponentFloat) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            Float floatMinus = this.minusExternal(float);
            (int256 signedCoefficientMinus, int256 exponentMinus) = floatMinus.unpack();
            assertEq(signedCoefficient, signedCoefficientMinus);
            assertEq(exponent, exponentMinus);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.minusExternal(float);
        }
    }
}
