// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float, ExponentOverflow, ExponentUnderflow} from "src/lib/LibDecimalFloat.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {Test} from "forge-std-1.17.0/src/Test.sol";

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

    /// `mul` of two operands whose exponents sum below `int32.min` reverts
    /// instead of silently producing `FLOAT_ZERO`. Without this, downstream
    /// code that branches on `result == 0` would mistake a tiny magnitude
    /// for an exact zero. The product `1 × 1` needs no digit shed, so the
    /// error carries it at the exponent sum.
    function testMulRevertsOnExponentUnderflow() external {
        Float a = LibDecimalFloat.packLossless(1, type(int32).min);
        Float b = LibDecimalFloat.packLossless(1, type(int32).min);
        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, int256(1), int256(-4294967296)));
        this.mulExternal(a, b);
    }

    /// A product that fits int224 one exponent above `int32.max` but has no
    /// headroom to lift back down overflows with the unshed product:
    /// `1e67 × 10^(int32.max + 1)` is `1e68 × 10^int32.max`.
    function testMulOverflowPastLiftHeadroom() external {
        assertTrue(LibTestExactDecimal.mulOverflows(1e67, type(int32).max, 1, 1), "product overflows");
        (int256 signedCoefficient, int256 exponent) = LibTestExactDecimal.mulPayload(1e67, type(int32).max, 1, 1);
        vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficient, exponent));
        this.mulExternal(LibDecimalFloat.packLossless(1e67, type(int32).max), LibDecimalFloat.packLossless(1, 1));
    }

    /// Reverts only where the exact product is beyond the largest Float of its
    /// sign or below the smallest positive Float, otherwise is the nearest
    /// Float towards zero to the exact product, and agrees with the unpacked
    /// path.
    function testMulPacked(Float a, Float b) external {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        bool overflows = LibTestExactDecimal.mulOverflows(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        bool underflows =
            LibTestExactDecimal.mulUnderflows(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        if (overflows || underflows) {
            (int256 signedCoefficient, int256 exponent) =
                LibTestExactDecimal.mulPayload(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
            vm.expectRevert(
                abi.encodeWithSelector(
                    overflows ? ExponentOverflow.selector : ExponentUnderflow.selector, signedCoefficient, exponent
                )
            );
            this.mulExternal(a, b);
            return;
        }
        Float floatExternal = this.mulExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (int256 signedCoefficientParts, int256 exponentParts) = floatExternal.unpack();
        Float float = this.mulExternal(a, b);
        checkMulValue(a, b, float);
        (int256 signedCoefficientUnpacked, int256 exponentUnpacked) = float.unpack();
        assertEq(signedCoefficientParts, signedCoefficientUnpacked);
        assertEq(exponentParts, exponentUnpacked);
    }

    function checkMulValue(Float a, Float b, Float result) internal pure {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (int256 signedCoefficient, int256 exponent) = result.unpack();
        assertTrue(
            LibTestExactDecimal.isNearestTowardZero(
                (signedCoefficientA < 0) != (signedCoefficientB < 0),
                LibTestExactDecimal.mul(
                    LibTestExactDecimal.abs(signedCoefficientA), LibTestExactDecimal.abs(signedCoefficientB)
                ),
                exponentA + exponentB,
                signedCoefficient,
                exponent
            ),
            "nearest Float towards zero"
        );
    }

    /// #332: int224.min × -1 is 2^223, which packs as int224.max at the same
    /// exponent, as `minus` does.
    function testMulInt224MinNegativeOne() external pure {
        Float min = LibDecimalFloat.packLossless(type(int224).min, 0);
        Float product = min.mul(LibDecimalFloat.packLossless(-1, 0));
        assertEq(Float.unwrap(product), Float.unwrap(LibDecimalFloat.packLossless(type(int224).max, 0)));
        assertEq(Float.unwrap(product), Float.unwrap(min.minus()));
    }
}
