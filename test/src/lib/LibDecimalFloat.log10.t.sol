// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LogTest} from "../../abstract/LogTest.sol";

contract LibDecimalFloatLog10Test is LogTest {
    using LibDecimalFloat for Float;

    function log10External(int256 signedCoefficient, int256 exponent) external returns (int256, int256) {
        address tables = logTables();
        return LibDecimalFloatImplementation.log10(tables, signedCoefficient, exponent);
    }

    function log10External(Float float) external returns (Float) {
        return float.log10(logTables());
    }

    function testLog10Packed(Float float) external {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        try this.log10External(signedCoefficient, exponent) returns (
            int256 signedCoefficientResult, int256 exponentResult
        ) {
            Float floatLog10 = this.log10External(float);
            (int256 signedCoefficientResultUnpacked, int256 exponentResultUnpacked) = floatLog10.unpack();
            assertEq(signedCoefficientResultUnpacked, signedCoefficientResult);
            assertEq(exponentResultUnpacked, exponentResult);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.log10External(float);
        }
    }
}
