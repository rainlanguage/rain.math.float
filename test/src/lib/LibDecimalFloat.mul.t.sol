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
    /// for an exact zero.
    function testMulRevertsOnExponentUnderflow() external {
        Float a = LibDecimalFloat.packLossless(1, type(int32).min);
        Float b = LibDecimalFloat.packLossless(1, type(int32).min);
        vm.expectPartialRevert(ExponentUnderflow.selector);
        this.mulExternal(a, b);
    }

    /// Reverts only where the exact product is beyond the largest Float of its
    /// sign or below the smallest positive Float, and otherwise agrees with the
    /// unpacked path.
    function testMulPacked(Float a, Float b) external {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        bool overflows = LibTestExactDecimal.mulOverflows(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        bool underflows =
            LibTestExactDecimal.mulUnderflows(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        if (overflows || underflows) {
            (int256 signedCoefficient, int256 exponent) =
                LibDecimalFloatImplementation.mul(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
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
        (int256 signedCoefficientUnpacked, int256 exponentUnpacked) = float.unpack();
        assertEq(signedCoefficientParts, signedCoefficientUnpacked);
        assertEq(exponentParts, exponentUnpacked);
    }
}
