// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {
    LibDecimalFloat,
    NORMALIZED_ZERO_SIGNED_COEFFICIENT,
    NORMALIZED_ZERO_EXPONENT,
    Float,
    EXPONENT_MAX
} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibDecimalFloatSlow} from "test/lib/LibDecimalFloatSlow.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatMultiplyTest is Test {
    using LibDecimalFloat for Float;

    function multiplyExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (int256, int256)
    {
        return LibDecimalFloat.multiply(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    function multiplyExternal(Float memory floatA, Float memory floatB) external pure returns (Float memory) {
        return LibDecimalFloat.multiply(floatA, floatB);
    }

    /// Stack and mem are the same.
    function testMultiplyMem(Float memory a, Float memory b) external {
        try this.multiplyExternal(a.signedCoefficient, a.exponent, b.signedCoefficient, b.exponent) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            Float memory float = this.multiplyExternal(a, b);
            assertEq(signedCoefficient, float.signedCoefficient);
            assertEq(exponent, float.exponent);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.multiplyExternal(a, b);
        }
    }

    /// Simple 0 multiply 0
    /// 0 * 0 = 0
    function testMultiplyZero0Exponent() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.multiply(0, 0, 0, 0);
        assertEq(signedCoefficient, NORMALIZED_ZERO_SIGNED_COEFFICIENT);
        assertEq(exponent, NORMALIZED_ZERO_EXPONENT);
    }

    /// 0 multiply 0 any exponent
    /// 0 * 0 = 0
    function testMultiplyZeroAnyExponent(int64 exponentA, int64 exponentB) external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.multiply(0, exponentA, 0, exponentB);
        assertEq(signedCoefficient, NORMALIZED_ZERO_SIGNED_COEFFICIENT);
        assertEq(exponent, NORMALIZED_ZERO_EXPONENT);
    }

    /// 0 multiply 1
    /// 0 * 1 = 0
    function testMultiplyZeroOne() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.multiply(0, 0, 1, 0);
        assertEq(signedCoefficient, NORMALIZED_ZERO_SIGNED_COEFFICIENT);
        assertEq(exponent, NORMALIZED_ZERO_EXPONENT);
    }

    /// 1 multiply 0
    /// 1 * 0 = 0
    function testMultiplyOneZero() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.multiply(1, 0, 0, 0);
        assertEq(signedCoefficient, NORMALIZED_ZERO_SIGNED_COEFFICIENT);
        assertEq(exponent, NORMALIZED_ZERO_EXPONENT);
    }

    /// 1 multiply 1
    /// 1 * 1 = 1
    function testMultiplyOneOne() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.multiply(1, 0, 1, 0);
        assertEq(signedCoefficient, 1);
        assertEq(exponent, 0);
    }

    /// 123456789 multiply 987654321
    /// 123456789 * 987654321 = 121932631112635269
    function testMultiply123456789987654321() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.multiply(123456789, 0, 987654321, 0);
        assertEq(signedCoefficient, 121932631112635269);
        assertEq(exponent, 0);
    }

    /// 123456789 multiply 987654321 with exponents
    /// 123456789 * 987654321 = 121932631112635269
    function testMultiply123456789987654321WithExponents(int128 exponentA, int128 exponentB) external pure {
        exponentA = int128(bound(exponentA, -127, 127));
        exponentB = int128(bound(exponentB, -127, 127));

        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloat.multiply(123456789, exponentA, 987654321, exponentB);
        assertEq(signedCoefficient, 121932631112635269);
        assertEq(exponent, exponentA + exponentB);
    }

    /// 1e18 * 1e-19 = 1e-1
    function testMultiply1e181e19() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.multiply(1, 18, 1, -19);
        assertEq(signedCoefficient, 1);
        assertEq(exponent, -1);
    }

    function testMultiplyGasZero() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.multiply(0, 0, 0, 0);
        (signedCoefficient, exponent);
    }

    function testMultiplyGasOne() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.multiply(1e37, -37, 1e37, -37);
        (signedCoefficient, exponent);
    }

    function testMultiplyNotRevertAnyExpectation(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB
    ) external pure {
        exponentA = bound(exponentA, -EXPONENT_MAX, EXPONENT_MAX);
        exponentB = bound(exponentB, -EXPONENT_MAX, EXPONENT_MAX);
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloat.multiply(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibDecimalFloatSlow.multiplySlow(signedCoefficientA, exponentA, signedCoefficientB, exponentB);

        assertEq(signedCoefficient, expectedSignedCoefficient);
        assertEq(exponent, expectedExponent);
    }
}
