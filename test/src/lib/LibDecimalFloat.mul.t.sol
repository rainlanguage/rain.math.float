// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float, ExponentUnderflow} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {Test} from "forge-std-1.16.1/src/Test.sol";

contract LibDecimalFloatMulTest is Test {
    using LibDecimalFloat for Float;

    function mulExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (Float)
    {
        (int256 signedCoefficientC, int256 exponentC) =
            LibDecimalFloatImplementation.mul(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        Float c = LibDecimalFloat.packArithmeticResult(signedCoefficientC, exponentC);
        return c;
    }

    function mulExternal(Float floatA, Float floatB) external pure returns (Float) {
        return LibDecimalFloat.mul(floatA, floatB);
    }

    /// `mul` of two operands whose exponents sum below `int32.min` reverts
    /// instead of silently producing `FLOAT_ZERO`. Without this, downstream
    /// code that branches on `result == 0` would mistake a tiny magnitude
    /// for an exact zero.
    function testMulRevertsOnExponentUnderflow() external {
        Float a = LibDecimalFloat.packLossless(1, type(int32).min);
        Float b = LibDecimalFloat.packLossless(1, type(int32).min);
        vm.expectPartialRevert(ExponentUnderflow.selector);
        this.mulExternal(a, b);
    }

    function testMulPacked(Float a, Float b) external {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        try this.mulExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB) returns (
            Float floatExternal
        ) {
            (int256 signedCoefficient, int256 exponent) = floatExternal.unpack();
            Float float = this.mulExternal(a, b);
            (int256 signedCoefficientUnpacked, int256 exponentUnpacked) = float.unpack();
            assertEq(signedCoefficient, signedCoefficientUnpacked);
            assertEq(exponent, exponentUnpacked);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.mulExternal(a, b);
        }
    }
}
