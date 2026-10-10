// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float, ExponentOverflow, ExponentUnderflow} from "src/lib/LibDecimalFloat.sol";
import {DivisionByZero} from "src/error/ErrDecimalFloat.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";

import {Test} from "forge-std-1.17.0/src/Test.sol";

contract LibDecimalFloatDivTest is Test {
    using LibDecimalFloat for Float;

    function divExternal(Float floatA, Float floatB) external pure returns (Float) {
        return LibDecimalFloat.div(floatA, floatB);
    }

    /// `div` whose result exponent (`expA - expB`) falls below `int32.min`
    /// reverts instead of silently producing `FLOAT_ZERO`. Constructed by
    /// numerator at the minimum exponent and denominator at the maximum. Both
    /// maximize to `1e76`, 76 below their exponents, and the quotient scales by
    /// `1e76`: `1e76 × 10^(int32.min - 76 - 76 - (int32.max - 76))`.
    function testDivRevertsOnExponentUnderflow() external {
        Float a = LibDecimalFloat.packLossless(1, type(int32).min);
        Float b = LibDecimalFloat.packLossless(1, type(int32).max);
        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, int256(1e76), int256(-4294967371)));
        this.divExternal(a, b);
    }

    /// Reverts only on a zero divisor, or where the exact quotient is beyond
    /// the largest Float of its sign or below the smallest positive Float, and
    /// otherwise is the Float closest to the exact quotient that does not
    /// exceed its magnitude.
    function testDivPacked(Float a, Float b) external {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        if (signedCoefficientB == 0) {
            vm.expectRevert(abi.encodeWithSelector(DivisionByZero.selector, signedCoefficientA, exponentA));
            this.divExternal(a, b);
            return;
        }
        bool overflows = LibTestExactDecimal.divOverflows(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        bool underflows =
            LibTestExactDecimal.divUnderflows(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        if (overflows || underflows) {
            (int256 signedCoefficient, int256 exponent) =
                LibTestExactDecimal.divParts(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
            vm.expectRevert(
                abi.encodeWithSelector(
                    overflows ? ExponentOverflow.selector : ExponentUnderflow.selector, signedCoefficient, exponent
                )
            );
            this.divExternal(a, b);
            return;
        }
        (int256 signedCoefficientExpected, int256 exponentExpected) =
            LibTestExactDecimal.divFloat(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (int256 signedCoefficientResult, int256 exponentResult) = this.divExternal(a, b).unpack();
        assertTrue(
            LibTestExactDecimal.eq(
                signedCoefficientResult, exponentResult, signedCoefficientExpected, exponentExpected
            ),
            "quotient"
        );
    }

    function testDivByOneFloat(int224 signedCoefficient, int32 exponent) external pure {
        exponent = int32(bound(exponent, int256(type(int32).min) + 65, int256(type(int32).max)));
        Float float = LibDecimalFloat.packLossless(signedCoefficient, exponent);
        int256 one = 1;
        for (int256 oneExponent = 0; oneExponent >= -65; --oneExponent) {
            Float result = LibDecimalFloat.div(float, LibDecimalFloat.packLossless(one, oneExponent));
            assertTrue(result.eq(float));
            if (oneExponent == -65) {
                break;
            }
            one *= 10;
        }
    }

    function testDivByNegativeOneFloat(int224 signedCoefficient, int32 exponent) external pure {
        exponent = int32(bound(exponent, int256(type(int32).min) + 65, int256(type(int32).max) - 65));
        Float float = LibDecimalFloat.packLossless(signedCoefficient, exponent);
        int256 negativeOne = -1;
        for (int256 oneExponent = 0; oneExponent >= -65; --oneExponent) {
            Float result = LibDecimalFloat.div(float, LibDecimalFloat.packLossless(negativeOne, oneExponent));
            assertTrue(result.eq(float.minus()));
            if (oneExponent == -65) {
                break;
            }
            negativeOne *= 10;
        }
    }

    /// #332: int224.min / -1 is 2^223, which packs as int224.max at the same
    /// exponent, as `minus` does.
    function testDivInt224MinNegativeOne() external pure {
        Float min = LibDecimalFloat.packLossless(type(int224).min, 0);
        Float quotient = min.div(LibDecimalFloat.packLossless(-1, 0));
        assertEq(Float.unwrap(quotient), Float.unwrap(LibDecimalFloat.packLossless(type(int224).max, 0)));
        assertEq(Float.unwrap(quotient), Float.unwrap(min.minus()));
    }
}
