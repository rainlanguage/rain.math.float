// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    LibDecimalFloatImplementation,
    EXPONENT_MIN,
    EXPONENT_MAX
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";
import {ExponentOverflow} from "src/error/ErrDecimalFloat.sol";

contract LibDecimalFloatImplementationMinusTest is Test {
    /// Minus is the exact `-x` at the same exponent, by the
    /// representable-range rule: only int256.min, whose negation 2^255 is no
    /// int256, sheds a digit.
    function testMinusMatchesRule(int256 signedCoefficient, int256 exponent) external pure {
        vm.assume(signedCoefficient != type(int256).min || exponent != type(int256).max);
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibTestExactDecimal.signedParts(signedCoefficient > 0, LibTestExactDecimal.abs(signedCoefficient), exponent);
        (int256 signedCoefficientMinus, int256 exponentMinus) =
            LibDecimalFloatImplementation.minus(signedCoefficient, exponent);
        assertEq(signedCoefficientMinus, expectedSignedCoefficient, "coefficient");
        assertEq(exponentMinus, expectedExponent, "exponent");
    }

    /// `-int256.min` is 2^255, which floors to
    /// 5789604461865809771178549250434395392663499233282028201972879200395656481996e1.
    function testMinusMinSignedValue(int256 exponent) external pure {
        exponent = bound(exponent, type(int256).min, type(int256).max - 1);
        (int256 signedCoefficientMinus, int256 exponentMinus) =
            LibDecimalFloatImplementation.minus(type(int256).min, exponent);
        assertEq(signedCoefficientMinus, 5789604461865809771178549250434395392663499233282028201972879200395656481996);
        assertEq(exponentMinus, exponent + 1);
    }

    /// a + (-a) == 0 for all in-range inputs.
    /// type(int256).min cannot be negated so it is excluded.
    function testAdditiveInverse(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
        vm.assume(signedCoefficient != type(int256).min);

        (int256 negCoeff, int256 negExp) = LibDecimalFloatImplementation.minus(signedCoefficient, exponent);
        (int256 sumCoeff,) = LibDecimalFloatImplementation.add(signedCoefficient, exponent, negCoeff, negExp);
        assertEq(sumCoeff, 0, "a + (-a) should be zero");
    }

    /// --a == a for all in-range inputs.
    /// type(int256).min cannot be negated so it is excluded.
    function testDoubleNegation(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, EXPONENT_MIN / 10, EXPONENT_MAX / 10);
        vm.assume(signedCoefficient != type(int256).min);

        (int256 negCoeff, int256 negExp) = LibDecimalFloatImplementation.minus(signedCoefficient, exponent);
        (int256 doubleNegCoeff, int256 doubleNegExp) = LibDecimalFloatImplementation.minus(negCoeff, negExp);

        assertTrue(
            LibDecimalFloatImplementation.eq(signedCoefficient, exponent, doubleNegCoeff, doubleNegExp),
            "double negation should be identity"
        );
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
