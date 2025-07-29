// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float, ExponentOverflow} from "src/lib/LibDecimalFloat.sol";
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

    function testPow10Packed(Float float) external {
        (int256 signedCoefficientFloat, int256 exponentFloat) = float.unpack();
        try this.pow10External(signedCoefficientFloat, exponentFloat) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            if (exponent > type(int32).max) {
                vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficient, exponent));
                this.pow10External(float);
            } else {
                Float floatPower10 = this.pow10External(float);
                (int256 signedCoefficientUnpacked, int256 exponentUnpacked) = floatPower10.unpack();
                assertEq(signedCoefficient, signedCoefficientUnpacked);
                assertEq(exponent, exponentUnpacked);
            }
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.pow10External(float);
        }
    }
}
