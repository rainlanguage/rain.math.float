// SPDX-License-Identifier: CAL
pragma solidity ^0.8.25;

import {
    DecimalFloat,
    LibDecimalFloat,
    COEFFICIENT_MASK,
    SignOverflow,
    ExponentOverflow,
    CoefficientOverflow
} from "src/DecimalFloat.sol";
import {Test} from "forge-std/Test.sol";

contract DecimalFloatPartsTest is Test {
    using LibDecimalFloat for DecimalFloat;

    /// Round trip from/to parts.
    function testPartsRoundTrip(uint256 sign, uint256 coefficient, int256 exponent) external pure {
        sign = bound(sign, 0, 1);
        coefficient = bound(coefficient, 0, COEFFICIENT_MASK);
        exponent = bound(exponent, type(int16).min, type(int16).max);

        DecimalFloat value = LibDecimalFloat.fromParts(sign, coefficient, exponent);
        (uint256 signOut, uint256 coefficientOut, int256 exponentOut) = value.toParts();
        assertEq(sign, signOut);
        assertEq(coefficient, coefficientOut);
        assertEq(exponent, exponentOut);
    }

    /// Out of bounds sign must error.
    function testSignOverflow(uint256 sign, uint256 coefficient, int256 exponent) external {
        sign = bound(sign, 2, type(uint256).max);
        coefficient = bound(coefficient, 0, COEFFICIENT_MASK);
        exponent = bound(exponent, type(int16).min, type(int16).max);
        vm.expectRevert(abi.encodeWithSelector(SignOverflow.selector, sign));
        LibDecimalFloat.fromParts(sign, coefficient, exponent);
    }

    /// Out of bounds low exponent must error.
    function testExponentOverflowLow(uint256 sign, uint256 coefficient, int256 exponent) external {
        sign = bound(sign, 0, 1);
        coefficient = bound(coefficient, 0, COEFFICIENT_MASK);
        exponent = bound(exponent, type(int256).min, int256(type(int16).min) - 1);
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, exponent));
        LibDecimalFloat.fromParts(sign, coefficient, exponent);
    }

    /// Out of bounds high exponent must error.
    function testExponentOverflowHigh(uint256 sign, uint256 coefficient, int256 exponent) external {
        sign = bound(sign, 0, 1);
        coefficient = bound(coefficient, 0, COEFFICIENT_MASK);
        exponent = bound(exponent, int256(type(int16).max) + 1, type(int256).max);
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, exponent));
        LibDecimalFloat.fromParts(sign, coefficient, exponent);
    }

    /// Out of bounds coefficient must error.
    function testCoefficientOverflow(uint256 sign, uint256 coefficient, int256 exponent) external {
        sign = bound(sign, 0, 1);
        coefficient = bound(coefficient, COEFFICIENT_MASK + 1, type(uint256).max);
        exponent = bound(exponent, type(int16).min, type(int16).max);
        vm.expectRevert(abi.encodeWithSelector(CoefficientOverflow.selector, coefficient));
        LibDecimalFloat.fromParts(sign, coefficient, exponent);
    }
}
