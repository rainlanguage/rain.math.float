// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Log10Zero, Log10Negative} from "src/error/ErrDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";

contract LibDecimalFloatLog10Test is Test {
    using LibDecimalFloat for Float;

    function log10External(int256 signedCoefficient, int256 exponent) external pure returns (Float) {
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.log10(signedCoefficient, exponent);
        (Float float, bool lossless) = LibDecimalFloat.packLossy(signedCoefficient, exponent);
        (lossless);
        return float;
    }

    function log10External(Float float) external pure returns (Float) {
        return float.log10();
    }

    /// log10 matches its implementation packed, and reverts only for 0 or a
    /// negative, with the error that names it.
    function testLog10Packed(Float float) external {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        if (signedCoefficient == 0) {
            vm.expectRevert(abi.encodeWithSelector(Log10Zero.selector));
            this.log10External(float);
        } else if (signedCoefficient < 0) {
            vm.expectRevert(abi.encodeWithSelector(Log10Negative.selector, signedCoefficient, exponent));
            this.log10External(float);
        } else {
            (int256 signedCoefficientResult, int256 exponentResult) =
                this.log10External(signedCoefficient, exponent).unpack();
            (int256 signedCoefficientResultUnpacked, int256 exponentResultUnpacked) = this.log10External(float).unpack();
            assertEq(signedCoefficientResultUnpacked, signedCoefficientResult);
            assertEq(exponentResultUnpacked, exponentResult);
        }
    }
}
