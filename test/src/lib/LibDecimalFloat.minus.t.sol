// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, EXPONENT_MIN, EXPONENT_MAX} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatSubTest is Test {
    /// Minus is the same as `0 - x`.
    function testMinusIsSubZero(int256 exponentZero, int256 signedCoefficient, int256 exponent) external pure {
        exponentZero = bound(exponentZero, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
        exponent = bound(exponent, EXPONENT_MIN / 10, EXPONENT_MAX / 10);

        (int256 signedCoefficientMinus, int256 exponentMinus) = LibDecimalFloat.minus(signedCoefficient, exponent);
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibDecimalFloat.sub(0, exponentZero, signedCoefficient, exponent);

        assertEq(signedCoefficientMinus, expectedSignedCoefficient);
        assertEq(exponentMinus, expectedExponent);
    }
}
