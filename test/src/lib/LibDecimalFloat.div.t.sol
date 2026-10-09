// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float, ExponentOverflow, ExponentUnderflow} from "src/lib/LibDecimalFloat.sol";
import {DivisionByZero} from "src/error/ErrDecimalFloat.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {Test} from "forge-std-1.17.0/src/Test.sol";

contract LibDecimalFloatDivTest is Test {
    using LibDecimalFloat for Float;

    function divExternal(Float floatA, Float floatB) external pure returns (Float) {
        return LibDecimalFloat.div(floatA, floatB);
    }

    /// `div` whose quotient is below the smallest positive Float reverts
    /// instead of silently producing `FLOAT_ZERO`, reporting `a`.
    function testDivRevertsOnExponentUnderflow() external {
        Float a = LibDecimalFloat.packLossless(1, type(int32).min);
        Float b = LibDecimalFloat.packLossless(1, type(int32).max);
        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, int256(1), int256(type(int32).min)));
        this.divExternal(a, b);
    }

    /// `div` whose quotient is past the largest Float reverts, reporting `a`.
    function testDivRevertsOnExponentOverflow() external {
        Float a = LibDecimalFloat.packLossless(-7, type(int32).max);
        Float b = LibDecimalFloat.packLossless(1, type(int32).min);
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, int256(-7), int256(type(int32).max)));
        this.divExternal(a, b);
    }

    /// The least quotient past the largest Float, `(int224.max / 10 + 1)
    /// 10^(int32.max + 1)`, reverts reporting `a`, and the one just below it is
    /// the largest Float, for both signs.
    function testDivAtTheOverflowThreshold(bool negative) external {
        int256 sign = negative ? int256(-1) : int256(1);
        int256 threshold = type(int224).max / 10 + 1;
        Float a = LibDecimalFloat.packLossless(sign * threshold, type(int32).max);
        Float b = LibDecimalFloat.packLossless(1, -1);
        vm.expectRevert(
            abi.encodeWithSelector(ExponentOverflow.selector, sign * threshold, int256(type(int32).max))
        );
        this.divExternal(a, b);

        Float below = LibDecimalFloat.packLossless(sign * (threshold - 1), type(int32).max);
        Float quotient = this.divExternal(below, b);
        (int256 signedCoefficient, int256 exponent) = quotient.unpack();
        assertEq(signedCoefficient, sign * (threshold - 1) * 10, "coefficient");
        assertEq(exponent, int256(type(int32).max), "exponent");
    }

    /// A quotient in range past the ceiling less ten is not a range error.
    function testDivNearTheCeiling() external view {
        Float a = LibDecimalFloat.packLossless(5, type(int32).max);
        Float quotient = this.divExternal(a, LibDecimalFloat.packLossless(2, 0));
        assertTrue(quotient.eq(LibDecimalFloat.packLossless(25, int256(type(int32).max) - 1)));
    }

    /// The Float closest to the exact `a / b` that does not exceed its
    /// magnitude: the exact quotient to 76 digits, packed.
    function expectedQuotient(int256 ca, int256 ea, int256 cb, int256 eb) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = LibTestExactDecimal.quotient76(ca, ea, cb, eb);
        (Float expected,) = LibDecimalFloat.packLossy(signedCoefficient, exponent);
        return expected;
    }

    /// Reverts only on a zero divisor, or where the exact quotient is beyond
    /// the largest Float of its sign or below the smallest positive Float, with
    /// `a` as the range error's payload. Otherwise the quotient is the Float
    /// closest to the exact one that does not exceed its magnitude.
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
            vm.expectRevert(
                abi.encodeWithSelector(
                    overflows ? ExponentOverflow.selector : ExponentUnderflow.selector, signedCoefficientA, exponentA
                )
            );
            this.divExternal(a, b);
            return;
        }
        Float quotient = this.divExternal(a, b);
        if (signedCoefficientA == 0) {
            assertEq(Float.unwrap(quotient), Float.unwrap(LibDecimalFloat.FLOAT_ZERO), "zero");
            return;
        }
        assertEq(
            Float.unwrap(quotient),
            Float.unwrap(expectedQuotient(signedCoefficientA, exponentA, signedCoefficientB, exponentB)),
            "quotient"
        );
    }

    function divPartsExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (int256, int256)
    {
        return LibDecimalFloatImplementation.div(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// #374: the parts `div` hands to packing are the exact quotient truncated
    /// as its NatSpec states.
    function testDivPartsMatchRule(Float a, Float b) external view {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        vm.assume(signedCoefficientB != 0);
        (int256 signedCoefficient, int256 exponent) =
            this.divPartsExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (int256 expectedSignedCoefficient, int256 expectedExponent) =
            LibTestExactDecimal.divParts(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(signedCoefficient, expectedSignedCoefficient, "coefficient");
        assertEq(exponent, expectedExponent, "exponent");
        assertTrue(
            LibTestExactDecimal.isTruncatedQuotient(
                signedCoefficientA, exponentA, signedCoefficientB, exponentB, signedCoefficient, exponent
            ),
            "truncated quotient"
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
