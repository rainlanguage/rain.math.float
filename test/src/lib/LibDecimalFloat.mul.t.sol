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

    /// An operand exponent above `EXPONENT_MAX` is out of the arithmetic
    /// domain and must surface as `ExponentOverflow(signedCoefficientA,
    /// exponentA)`, never fall through to the checked add and raise a raw
    /// `Panic(0x11)`.
    function testMulPositiveExponentOverflowRevert() external {
        int256 exponentA = type(int256).max;
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(1), exponentA));
        this.mulImplExternal(1, exponentA, 1, 1);
    }

    /// The domain bound is inclusive: an exponent pair summing to exactly
    /// `EXPONENT_MAX` must NOT revert and returns that exponent.
    function testMulExponentDomainBoundaryMaxNoRevert() external {
        (int256 signedCoefficient, int256 exponent) = this.mulImplExternal(1, EXPONENT_MAX, 1, 0);
        assertEq(exponent, EXPONENT_MAX);
        assertEq(signedCoefficient, 1);
    }

    /// In-domain operands whose exponents sum past `EXPONENT_MAX` revert
    /// `ExponentOverflow` on the result rather than returning an out-of-domain
    /// exponent.
    function testMulPositiveExponentBoundaryRevert() external {
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(1), EXPONENT_MAX + 1));
        this.mulImplExternal(1, EXPONENT_MAX, 1, 1);
    }

    /// The operand domain check is not a same-sign sum check: an out-of-domain
    /// positive operand exponent reverts even when the opposite-sign pair sums
    /// back inside the domain.
    function testMulPositiveOutOfDomainOperandOppositeSignReverts() external {
        int256 exponentA = type(int256).max;
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(1), exponentA));
        this.mulImplExternal(1, exponentA, 1, -5);
    }

    /// An operand exponent below `EXPONENT_MIN` is out of the arithmetic
    /// domain and must surface as `ExponentOverflow(signedCoefficientA,
    /// exponentA)`, never as a raw `Panic(0x11)`.
    function testMulNegativeExponentOverflowReverts() external {
        int256 exponentA = type(int256).min;
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(1), exponentA));
        this.mulImplExternal(1, exponentA, 1, -1);
    }

    /// The domain bound is inclusive: an exponent pair summing to exactly
    /// `EXPONENT_MIN` must NOT revert and returns that exponent.
    function testMulExponentDomainBoundaryMinNoRevert() external {
        (int256 signedCoefficient, int256 exponent) = this.mulImplExternal(1, EXPONENT_MIN, 1, 0);
        assertEq(exponent, EXPONENT_MIN);
        assertEq(signedCoefficient, 1);
    }

    /// In-domain operands whose exponents sum below `EXPONENT_MIN` revert
    /// `ExponentOverflow` on the result rather than returning an out-of-domain
    /// exponent.
    function testMulNegativeExponentBoundaryRevert() external {
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(1), EXPONENT_MIN - 1));
        this.mulImplExternal(1, EXPONENT_MIN, 1, -1);
    }

    /// The operand domain check is not a same-sign sum check: an out-of-domain
    /// negative operand exponent reverts even when the opposite-sign pair sums
    /// back inside the domain.
    function testMulNegativeOutOfDomainOperandOppositeSignReverts() external {
        int256 exponentA = type(int256).min;
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(1), exponentA));
        this.mulImplExternal(1, exponentA, 1, 5);
    }

    /// The `ExponentOverflow` payload for an out-of-domain operand carries
    /// that operand's coefficient and exponent (`signedCoefficientA`,
    /// `exponentA`), not the second operand's.
    function testMulExponentOverflowPayloadIsFirstOperand() external {
        int256 exponentA = type(int256).max;
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(3), exponentA));
        this.mulImplExternal(3, exponentA, 7, 5);
    }

    /// The second operand is domain-checked independently of the first: an
    /// out-of-domain `exponentB` reverts with the SECOND operand's payload.
    function testMulOutOfDomainOperandBReverts() external {
        int256 exponentB = type(int256).max;
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(3), exponentB));
        this.mulImplExternal(7, 5, 3, exponentB);
    }

    /// Two in-domain operands at the domain maximum with coefficients large
    /// enough to renormalize would overflow int256 in the exponent adjustment;
    /// the guard surfaces ExponentOverflow with the pre-adjustment sum instead
    /// of a raw Panic(0x11).
    function testMulRenormalizationOverflowGuard() external {
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(1e75), type(int256).max - 1));
        this.mulImplExternal(1e75, EXPONENT_MAX, 1e75, EXPONENT_MAX);
    }

    /// Opposite-sign exponents at the extreme domain bounds are in-domain
    /// operands; they simply add and cancel.
    function testMulOppositeSignExponentsDoNotRevert() external {
        (int256 signedCoefficient, int256 exponent) = this.mulImplExternal(2, EXPONENT_MAX, 3, EXPONENT_MIN);
        assertEq(signedCoefficient, 6, "coefficient");
        assertEq(exponent, 0, "exponent");
    }

    /// The coefficient rounding in `unabsUnsignedMulOrDivLossy` can push the
    /// exponent one past a sum that still sat at the domain bound; the result
    /// check must catch it.
    function testMulCoefficientRoundingPastDomainMaxReverts() external {
        // 8e75 * 10 = 8e76 > int256.max, so the coefficient rounds to 8e75
        // and the exponent picks up one more.
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(8e75), EXPONENT_MAX + 1));
        this.mulImplExternal(8e75, EXPONENT_MAX, 10, 0);
    }

    /// Same coefficient rounding one below the domain bound lands exactly on
    /// `EXPONENT_MAX` and must NOT revert.
    function testMulCoefficientRoundingToDomainMaxNoRevert() external {
        (int256 signedCoefficient, int256 exponent) = this.mulImplExternal(8e75, EXPONENT_MAX - 1, 10, 0);
        assertEq(signedCoefficient, 8e75, "coefficient");
        assertEq(exponent, EXPONENT_MAX, "exponent");
    }
}
