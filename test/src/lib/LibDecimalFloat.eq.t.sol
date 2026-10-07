// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";

contract LibDecimalFloatEqTest is Test {
    using LibDecimalFloat for Float;

    function eqExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (bool)
    {
        return LibDecimalFloatImplementation.eq(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    function eqExternal(Float floatA, Float floatB) external pure returns (bool) {
        return LibDecimalFloat.eq(floatA, floatB);
    }

    /// Never reverts, and answers exact numeric equality on both paths.
    function testEqPacked(Float a, Float b) external view {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        bool expected = LibTestExactDecimal.eq(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        assertEq(this.eqExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB), expected, "unpacked");
        assertEq(this.eqExternal(a, b), expected, "packed");
    }

    /// xeX != yeY if xeX < xeY || xeX > xeY
    function testEqXNotYExponents(Float a, Float b) external pure {
        bool eq = a.eq(b);
        bool lt = a.lt(b);
        bool gt = a.gt(b);

        assertEq(eq, !lt && !gt);
    }

    /// Test some zeros.
    function testEqZero(int32 exponent) external pure {
        Float wrapZero = Float.wrap(0);
        Float packZeroBasic = LibDecimalFloat.packLossless(0, 0);
        Float packZero = LibDecimalFloat.packLossless(0, exponent);

        assertTrue(wrapZero.eq(packZero));
        assertTrue(wrapZero.eq(packZeroBasic));
        assertEq(Float.unwrap(wrapZero), Float.unwrap(packZeroBasic));
    }
}
