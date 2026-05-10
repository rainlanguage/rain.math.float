// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibDecimalFloat, Float, ExponentUnderflow} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

contract LibDecimalFloatInvTest is Test {
    using LibDecimalFloat for Float;

    function invExternal(int256 signedCoefficient, int256 exponent) external pure returns (Float) {
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.inv(signedCoefficient, exponent);
        Float float = LibDecimalFloat.packArithmeticResult(signedCoefficient, exponent);
        return float;
    }

    function invExternal(Float float) external pure returns (Float) {
        return LibDecimalFloat.inv(float);
    }

    /// `inv` of a Float whose representable inverse magnitude falls below
    /// `int32.min` reverts instead of silently producing `FLOAT_ZERO`.
    function testInvRevertsOnExponentUnderflow() external {
        Float float = Float.wrap(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        vm.expectPartialRevert(ExponentUnderflow.selector);
        this.invExternal(float);
    }

    function testInvMem(Float float) external {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        try this.invExternal(signedCoefficient, exponent) returns (Float floatParts) {
            (int256 signedCoefficientResult, int256 exponentResult) = floatParts.unpack();
            Float floatInv = this.invExternal(float);
            (int256 signedCoefficientResultUnpacked, int256 exponentResultUnpacked) = floatInv.unpack();
            assertEq(signedCoefficientResultUnpacked, signedCoefficientResult);
            assertEq(exponentResultUnpacked, exponentResult);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.invExternal(float);
        }
    }
}
