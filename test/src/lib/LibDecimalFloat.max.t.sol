// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

contract LibDecimalFloatMaxTest is Test {
    using LibDecimalFloat for Float;

    function maxExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (int256, int256)
    {
        return LibDecimalFloat.max(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    function maxExternal(Float memory floatA, Float memory floatB) external pure returns (Float memory) {
        return floatA.max(floatB);
    }
    /// Test to verify that stack-based and memory-based implementations produce the same results.

    function testMaxMem(Float memory a, Float memory b) external {
        try this.maxExternal(a.signedCoefficient, a.exponent, b.signedCoefficient, b.exponent) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            Float memory actual = this.maxExternal(a, b);
            assertEq(signedCoefficient, actual.signedCoefficient);
            assertEq(exponent, actual.exponent);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.maxExternal(a, b);
        }
    }
    /// x.max(x)

    function testMaxX(Float memory x) external pure {
        Float memory y = x.max(x);
        assertTrue(y.eq(x), "x.max(x) != x");
    }
    /// x.max(y) == y.max(x)

    function testMaxXY(Float memory x, Float memory y) external pure {
        Float memory maxXY = x.max(y);
        Float memory maxYX = y.max(x);
        assertTrue(maxXY.eq(maxYX), "maxXY != maxYX");
    }
    /// x.max(y) for x == y

    function testMaxXYEqual(Float memory x) external pure {
        Float memory y = Float(x.signedCoefficient, x.exponent);
        Float memory z = x.max(y);
        assertTrue(z.eq(x), "x.max(y) != x");
        assertTrue(z.eq(y), "x.max(y) != y");
    }
    /// x.max(y) for x > y

    function testMaxXYGreater(Float memory x, Float memory y) external pure {
        vm.assume(x.gt(y));
        Float memory z = x.max(y);
        assertTrue(z.eq(x), "x.max(y) == x");
        assertTrue(!z.eq(y), "x.max(y) != y");
    }
    /// x.max(y) for x < y

    function testMaxXYLess(Float memory x, Float memory y) external pure {
        vm.assume(x.lt(y));
        Float memory z = x.max(y);
        assertTrue(!z.eq(x), "x.max(y) != x");
        assertTrue(z.eq(y), "x.max(y) == y");
    }
}
