// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float, EXPONENT_MIN, EXPONENT_MAX} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatMultiplyTest is Test {
    using LibDecimalFloat for Float;

    function multiplyExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (int256, int256)
    {
        return LibDecimalFloatImplementation.multiply(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    function multiplyExternal(Float floatA, Float floatB) external pure returns (Float) {
        return LibDecimalFloat.multiply(floatA, floatB);
    }

    function testMultiplyPacked(Float a, Float b) external {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        try this.multiplyExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            Float float = this.multiplyExternal(a, b);
            (int256 signedCoefficientUnpacked, int256 exponentUnpacked) = float.unpack();
            assertEq(signedCoefficient, signedCoefficientUnpacked);
            assertEq(exponent, exponentUnpacked);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.multiplyExternal(a, b);
        }
    }
}
