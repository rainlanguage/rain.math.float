// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float, ExponentOverflow, ExponentUnderflow} from "src/lib/LibDecimalFloat.sol";
import {LogTest} from "../../abstract/LogTest.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

contract LibDecimalFloatPow10Test is LogTest {
    using LibDecimalFloat for Float;

    function pow10External(int256 signedCoefficient, int256 exponent) external returns (int256, int256) {
        return LibDecimalFloatImplementation.pow10(logTables(), signedCoefficient, exponent);
    }

    function pow10External(Float float) external returns (Float) {
        return LibDecimalFloat.pow10(float, logTables());
    }

    /// `pow10` of an input whose effective result exponent falls below
    /// `int32.min` reverts instead of silently producing `FLOAT_ZERO`.
    function testPow10RevertsOnExponentUnderflow() external {
        Float float = Float.wrap(0xffffffffffffffffffffff0000000000000000000000000000000000000000ff);
        vm.expectPartialRevert(ExponentUnderflow.selector);
        this.pow10External(float);
    }

    function testPow10Packed(Float float) external {
        (int256 signedCoefficientFloat, int256 exponentFloat) = float.unpack();
        try this.pow10External(signedCoefficientFloat, exponentFloat) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            if (exponent > type(int32).max) {
                vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficient, exponent));
                this.pow10External(float);
            } else {
                // Predict whether packArithmeticResult will revert on underflow.
                (Float predicted, bool lossless) = LibDecimalFloat.packLossy(signedCoefficient, exponent);
                if (!lossless && Float.unwrap(predicted) == bytes32(0)) {
                    vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, signedCoefficient, exponent));
                    this.pow10External(float);
                } else {
                    Float floatPower10 = this.pow10External(float);
                    (int256 signedCoefficientUnpacked, int256 exponentUnpacked) = floatPower10.unpack();
                    (signedCoefficient, exponent) = predicted.unpack();
                    assertEq(signedCoefficient, signedCoefficientUnpacked);
                    assertEq(exponent, exponentUnpacked);
                }
            }
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.pow10External(float);
        }
    }
}
