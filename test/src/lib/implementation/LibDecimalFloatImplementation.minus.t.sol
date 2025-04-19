// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {
    LibDecimalFloatImplementation,
    EXPONENT_MIN,
    EXPONENT_MAX
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatImplementationMinusTest is Test {
    /// Minus is the same as `0 - x`.
    function testMinusIsSubZero(int256 exponentZero, int256 signedCoefficient, int256 exponent) external pure {
        exponentZero = bound(exponentZero, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
        exponent = bound(exponent, EXPONENT_MIN / 10, EXPONENT_MAX / 10);

        (int256 signedCoefficientMinus, int256 exponentMinus) =
            LibDecimalFloatImplementation.minus(signedCoefficient, exponent);
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibDecimalFloatImplementation.sub(0, exponentZero, signedCoefficient, exponent);

        assertEq(signedCoefficientMinus, expectedSignedCoefficient);
        assertEq(exponentMinus, expectedExponent);
    }
}
