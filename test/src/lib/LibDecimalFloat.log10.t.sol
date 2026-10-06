// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Log10Zero, Log10Negative} from "src/error/ErrDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LogTest} from "../../abstract/LogTest.sol";

contract LibDecimalFloatLog10Test is LogTest {
    using LibDecimalFloat for Float;

    function log10External(int256 signedCoefficient, int256 exponent) external returns (Float) {
        address tables = logTables();
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.log10(tables, signedCoefficient, exponent);
        (Float float, bool lossless) = LibDecimalFloat.packLossy(signedCoefficient, exponent);
        (lossless);
        return float;
    }

    function log10External(Float float) external returns (Float) {
        return float.log10(logTables());
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
