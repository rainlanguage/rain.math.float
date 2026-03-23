// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    LibDecimalFloatImplementation,
    EXPONENT_MIN,
    EXPONENT_MAX
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Test} from "forge-std/Test.sol";
import {ExponentOverflow} from "src/error/ErrDecimalFloat.sol";

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

    function minusExternal(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.minus(signedCoefficient, exponent);
    }

    /// minus reverts with ExponentOverflow when coefficient is type(int256).min
    /// and exponent is type(int256).max, because normalizing requires exponent + 1.
    function testMinusExponentOverflow() external {
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, type(int256).min, type(int256).max));
        this.minusExternal(type(int256).min, type(int256).max);
    }
}
