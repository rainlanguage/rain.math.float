// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float, ExponentUnderflow} from "src/lib/LibDecimalFloat.sol";
import {
    LibDecimalFloatImplementation,
    EXPONENT_MAX,
    EXPONENT_MIN
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {ExponentOverflow} from "src/error/ErrDecimalFloat.sol";

import {Test} from "forge-std-1.16.1/src/Test.sol";

contract LibDecimalFloatMulTest is Test {
    using LibDecimalFloat for Float;

    function mulExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (Float)
    {
        (int256 signedCoefficientC, int256 exponentC) =
            LibDecimalFloatImplementation.mul(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        Float c = LibDecimalFloat.packArithmeticResult(signedCoefficientC, exponentC);
        return c;
    }

    function mulExternal(Float floatA, Float floatB) external pure returns (Float) {
        return LibDecimalFloat.mul(floatA, floatB);
    }

    /// Raw wrapper over the stack-only implementation that returns the
    /// unpacked `(signedCoefficient, exponent)` directly. Packing would clamp
    /// or re-revert the extreme exponents these tests exercise, so the
    /// exponent-overflow guard must be observed on the raw impl result.
    function mulImplExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (int256, int256)
    {
        return LibDecimalFloatImplementation.mul(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// `mul` of two operands whose exponents sum below `int32.min` reverts
    /// instead of silently producing `FLOAT_ZERO`. Without this, downstream
    /// code that branches on `result == 0` would mistake a tiny magnitude
    /// for an exact zero.
    function testMulRevertsOnExponentUnderflow() external {
        Float a = LibDecimalFloat.packLossless(1, type(int32).min);
        Float b = LibDecimalFloat.packLossless(1, type(int32).min);
        vm.expectPartialRevert(ExponentUnderflow.selector);
        this.mulExternal(a, b);
    }

    function testMulPacked(Float a, Float b) external {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        try this.mulExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB) returns (
            Float floatExternal
        ) {
            (int256 signedCoefficient, int256 exponent) = floatExternal.unpack();
            Float float = this.mulExternal(a, b);
            (int256 signedCoefficientUnpacked, int256 exponentUnpacked) = float.unpack();
            assertEq(signedCoefficient, signedCoefficientUnpacked);
            assertEq(exponent, exponentUnpacked);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.mulExternal(a, b);
        }
    }

    /// Same-sign positive exponents whose sum overflows `int256` must surface
    /// as `ExponentOverflow(signedCoefficientA, exponentA)`, never fall through
    /// to the checked add and raise a raw `Panic(0x11)`.
    function testMulPositiveExponentOverflowRevert() external {
        int256 exponentA = type(int256).max;
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(1), exponentA));
        this.mulImplExternal(1, exponentA, 1, 1);
    }

    /// The positive guard is strict (`>`): a positive-exponent pair summing to
    /// exactly `int256.max` must NOT revert and returns that exponent.
    function testMulPositiveExponentBoundaryNoRevert() external {
        int256 exponentB = 1000;
        int256 exponentA = type(int256).max - exponentB;
        (int256 signedCoefficient, int256 exponent) = this.mulImplExternal(1, exponentA, 1, exponentB);
        assertEq(exponent, type(int256).max);
        assertEq(signedCoefficient, 1);
    }

    /// The positive guard is same-sign only: an opposite-sign pair (A>0, B<0)
    /// is exempt and returns the plain sum. The `exponentB > 0` predicate also
    /// stops the guard's own `type(int256).max - exponentB` subtraction from
    /// overflowing for a negative `exponentB`.
    function testMulPositiveGuardOppositeSignNoRevert() external {
        int256 exponentA = type(int256).max;
        int256 exponentB = -5;
        (int256 signedCoefficient, int256 exponent) = this.mulImplExternal(1, exponentA, 1, exponentB);
        assertEq(exponent, type(int256).max - 5);
        assertEq(signedCoefficient, 1);
    }

    /// Same-sign negative exponents whose sum underflows `int256` must surface
    /// as `ExponentOverflow(signedCoefficientA, exponentA)`, never as a raw
    /// `Panic(0x11)`.
    function testMulNegativeExponentOverflowReverts() external {
        int256 exponentA = type(int256).min;
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(1), exponentA));
        this.mulImplExternal(1, exponentA, 1, -1);
    }

    /// The negative guard is strict (`<`): a negative-exponent pair summing to
    /// exactly `int256.min` must NOT revert and returns that exponent.
    function testMulNegativeExponentBoundaryNoRevert() external {
        int256 exponentB = -1000;
        int256 exponentA = type(int256).min - exponentB;
        (int256 signedCoefficient, int256 exponent) = this.mulImplExternal(1, exponentA, 1, exponentB);
        assertEq(exponent, type(int256).min);
        assertEq(signedCoefficient, 1);
    }

    /// The negative guard is same-sign only: an opposite-sign pair (A<0, B>0)
    /// is exempt and returns the plain sum. The `exponentB < 0` predicate also
    /// stops the guard's `type(int256).min - exponentB` subtraction from
    /// underflowing for a positive `exponentB`.
    function testMulNegativeGuardOppositeSignNoRevert() external {
        int256 exponentA = type(int256).min;
        int256 exponentB = 5;
        (int256 signedCoefficient, int256 exponent) = this.mulImplExternal(1, exponentA, 1, exponentB);
        assertEq(exponent, type(int256).min + 5);
        assertEq(signedCoefficient, 1);
    }

    /// The `ExponentOverflow` payload carries the FIRST operand's coefficient
    /// and exponent (`signedCoefficientA`, `exponentA`), not the second.
    function testMulExponentOverflowPayloadIsFirstOperand() external {
        int256 exponentA = type(int256).max;
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(3), exponentA));
        this.mulImplExternal(3, exponentA, 7, 5);
    }

    /// Opposite-sign exponents never trip the same-sign overflow guard even at
    /// the extreme domain bounds; they simply add and cancel.
    function testMulOppositeSignExponentsDoNotRevert() external {
        (int256 signedCoefficient, int256 exponent) = this.mulImplExternal(2, EXPONENT_MAX, 3, EXPONENT_MIN);
        assertEq(signedCoefficient, 6, "coefficient");
        assertEq(exponent, 0, "exponent");
    }
}
