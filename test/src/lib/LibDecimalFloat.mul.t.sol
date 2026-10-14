// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float, ExponentOverflow, ExponentUnderflow} from "src/lib/LibDecimalFloat.sol";
import {LibExactFloat} from "test/lib/LibExactFloat.sol";
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

    /// int224.max × 8 is 107839786668602559178668060348078522694548577690162289924414440996856
    /// (`bc`), 69 digits. One digit sheds towards zero, to ...99685e1, where
    /// rounding to nearest would give ...99686e1.
    function testMulRoundsTowardsZero() external pure {
        int256 shed = 10783978666860255917866806034807852269454857769016228992441444099685;
        Float a = LibDecimalFloat.packLossless(type(int224).max, 0);
        Float eight = LibDecimalFloat.packLossless(8, 0);
        (int256 c, int256 e) = a.mul(eight).unpack();
        assertEq(c, shed);
        assertEq(e, 1);
        (c, e) = LibDecimalFloat.packLossless(type(int224).min + 1, 0).mul(eight).unpack();
        assertEq(c, -shed);
        assertEq(e, 1);
    }

    /// int224.min × -1 at int32.max is 2^223 × 10^int32.max, one unit past
    /// the largest Float, int224.max × 10^int32.max = (2^223 - 1) ×
    /// 10^int32.max. It packs to that Float rather than reverting.
    function testMulJustPastLargestFloatPacksToIt() external pure {
        Float largest = LibDecimalFloat.packLossless(type(int224).max, type(int32).max);
        Float p =
            LibDecimalFloat.packLossless(type(int224).min, type(int32).max).mul(LibDecimalFloat.packLossless(-1, 0));
        assertEq(Float.unwrap(p), Float.unwrap(largest));
    }

    /// `mul` of a product below every non-zero Float reverts instead of
    /// silently producing `FLOAT_ZERO`. Without this, downstream code that
    /// branches on `result == 0` would mistake a tiny magnitude for an exact
    /// zero. The product `1 × 1` needs no digit shed, so the error carries it
    /// at the exponent sum.
    function testMulRevertsOnExponentUnderflow() external {
        Float a = LibDecimalFloat.packLossless(1, type(int32).min);
        Float b = LibDecimalFloat.packLossless(1, type(int32).min);
        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, int256(1), int256(-4294967296)));
        this.mulExternal(a, b);
    }

    /// `ExponentUnderflow`'s NatSpec example: 1e-2147483648 × 0.1 is exactly
    /// 1 × 10^(int32.min - 1), below every non-zero Float, so the closest
    /// Float toward zero is zero and `mul` reverts with that product.
    function testMulUnderflowNatSpecExample() external {
        Float a = LibDecimalFloat.packLossless(1, type(int32).min);
        Float b = LibDecimalFloat.packLossless(1, -1);
        vm.expectRevert(abi.encodeWithSelector(ExponentUnderflow.selector, int256(1), int256(type(int32).min) - 1));
        this.mulExternal(a, b);
    }

    /// Exponents summing below `int32.min` are not underflow: 1e66 ×
    /// 10^int32.min times 1e66 × 10^-1 is exactly 1e132 × 10^(int32.min - 1),
    /// which is the Float 1e66 × 10^(int32.min + 65), so `mul` returns it.
    function testMulExponentSumBelowFloorIsNotUnderflow() external view {
        Float a = LibDecimalFloat.packLossless(1e66, type(int32).min);
        Float b = LibDecimalFloat.packLossless(1e66, -1);
        (int256 c, int256 e) = this.mulExternal(a, b).unpack();
        assertTrue(LibExactFloat.eq(c, e, 1e66, int256(type(int32).min) + 65), "product");
    }

    /// A product that fits int224 one exponent above `int32.max` but has no
    /// headroom to lift back down overflows with the unshed product:
    /// `1e67 × 10^(int32.max + 1)` is `1e68 × 10^int32.max`.
    function testMulOverflowPastLiftHeadroom() external {
        assertTrue(LibExactFloat.mulOverflows(1e67, type(int32).max, 1, 1), "product overflows");
        (int256 signedCoefficient, int256 exponent) = LibExactFloat.mulPayload(1e67, type(int32).max, 1, 1);
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
        bool overflows = LibExactFloat.mulOverflows(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        bool underflows = LibExactFloat.mulUnderflows(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        if (overflows || underflows) {
            (int256 signedCoefficient, int256 exponent) =
                LibExactFloat.mulPayload(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
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
            LibExactFloat.isNearestTowardZero(
                (signedCoefficientA < 0) != (signedCoefficientB < 0),
                LibExactFloat.mul(LibExactFloat.abs(signedCoefficientA), LibExactFloat.abs(signedCoefficientB)),
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
