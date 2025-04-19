// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatDivideTest is Test {
    using LibDecimalFloat for Float;

    function divideExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (int256, int256)
    {
        return LibDecimalFloatImplementation.divide(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    function divideExternal(Float floatA, Float floatB) external pure returns (Float) {
        return LibDecimalFloat.divide(floatA, floatB);
    }

    function testDividePacked(Float a, Float b) external {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        try this.divideExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            Float float = this.divideExternal(a, b);
            (int256 signedCoefficientFloat, int256 exponentFloat) = float.unpack();
            assertEq(signedCoefficient, signedCoefficientFloat);
            assertEq(exponent, exponentFloat);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.divideExternal(a, b);
        }
    }
}
