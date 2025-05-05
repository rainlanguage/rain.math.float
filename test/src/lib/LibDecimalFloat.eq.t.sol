// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

import {Test} from "forge-std/Test.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

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

    function testEqPacked(Float a, Float b) external {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        try this.eqExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB) returns (bool eq) {
            bool actual = this.eqExternal(a, b);
            assertEq(eq, actual);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.eqExternal(a, b);
        }
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
