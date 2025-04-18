// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LogTest} from "../../abstract/LogTest.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

contract LibDecimalFloatPower10Test is LogTest {
    using LibDecimalFloat for Float;

    function power10External(int256 signedCoefficient, int256 exponent) external returns (int256, int256) {
        address tables = logTables();
        return LibDecimalFloatImplementation.power10(tables, signedCoefficient, exponent);
    }

    function power10External(Float float) external returns (Float) {
        address tables = logTables();
        return LibDecimalFloat.power10(tables, float);
    }
    /// Stack and mem are the same.

    function testPower10Mem(Float float) external {
        (int256 signedCoefficientFloat, int256 exponentFloat) = float.unpack();
        try this.power10External(signedCoefficientFloat, exponentFloat) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            Float floatPower10 = this.power10External(float);
            (int256 signedCoefficientUnpacked, int256 exponentUnpacked) = floatPower10.unpack();
            assertEq(signedCoefficient, signedCoefficientUnpacked);
            assertEq(exponent, exponentUnpacked);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.power10External(float);
        }
    }
}
