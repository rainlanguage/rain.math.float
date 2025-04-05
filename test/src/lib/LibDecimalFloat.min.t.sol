// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

contract LibDecimalFloatMinTest is Test {
    using LibDecimalFloat for Float;

    function minExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (int256, int256)
    {
        return LibDecimalFloat.min(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    function minExternal(Float memory floatA, Float memory floatB) external pure returns (Float memory) {
        return floatA.min(floatB);
    }

    /// Test to verify that stack-based and memory-based implementations produce the same results.
    function testMinMem(Float memory a, Float memory b) external {
        try this.minExternal(a.signedCoefficient, a.exponent, b.signedCoefficient, b.exponent) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            Float memory actual = this.minExternal(a, b);
            assertEq(signedCoefficient, actual.signedCoefficient);
            assertEq(exponent, actual.exponent);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.minExternal(a, b);
        }
    }

    /// x.min(x)
    function testMinX(Float memory x) external pure {
        Float memory y = x.min(x);
        assertTrue(y.eq(x), "x.min(x) != x");
    }

    /// x.min(y) == y.min(x)
    function testMinXY(Float memory x, Float memory y) external pure {
        Float memory minXY = x.min(y);
        Float memory minYX = y.min(x);
        assertTrue(minXY.eq(minYX), "minXY != minYX");
    }

    /// x.min(y) for x == y
    function testMinXYEqual(Float memory x) external pure {
        Float memory y = Float(x.signedCoefficient, x.exponent);
        Float memory z = x.min(y);
        assertTrue(z.eq(x), "x.min(y) != x");
        assertTrue(z.eq(y), "x.min(y) != y");
    }

    /// x.min(y) for x < y
    function testMinXYLess(Float memory x, Float memory y) external pure {
        vm.assume(x.lt(y));
        Float memory z = x.min(y);
        assertTrue(z.eq(x), "x.min(y) != x");
        assertTrue(!z.eq(y), "x.min(y) == y");
    }

    /// x.min(y) for x > y
    function testMinXYGreater(Float memory x, Float memory y) external pure {
        vm.assume(x.gt(y));
        Float memory z = x.min(y);
        assertTrue(z.eq(y), "x.min(y) != y");
        assertTrue(!z.eq(x), "x.min(y) == x");
    }
}
