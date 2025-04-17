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

    function minExternal(Float floatA, Float floatB) external pure returns (Float) {
        return floatA.min(floatB);
    }

    /// Test to verify that stack-based and memory-based implementations produce the same results.
    function testMinMem(Float a, Float b) external {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        try this.minExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            Float actual = this.minExternal(a, b);
            (int256 signedCoefficientResult, int256 exponentResult) = actual.unpack();
            assertEq(signedCoefficient, signedCoefficientResult);
            assertEq(exponent, exponentResult);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.minExternal(a, b);
        }
    }

    /// x.min(x)
    function testMinX(Float x) external pure {
        Float y = x.min(x);
        assertTrue(y.eq(x), "x.min(x) != x");
    }

    /// x.min(y) == y.min(x)
    function testMinXY(Float x, Float y) external pure {
        Float minXY = x.min(y);
        Float minYX = y.min(x);
        assertTrue(minXY.eq(minYX), "minXY != minYX");
    }

    /// x.min(y) for x == y
    function testMinXYEqual(int256 signedCoefficientX, int256 exponentX) external pure {
        int256 signedCoefficientY = signedCoefficientX;
        int256 exponentY = exponentX;
        (int256 signedCoefficientZ, int256 exponentZ) =
            LibDecimalFloat.min(signedCoefficientX, exponentX, signedCoefficientY, exponentY);
        assertEq(signedCoefficientZ, signedCoefficientX, "signedCoefficientZ != signedCoefficientX");
        assertEq(exponentZ, exponentX, "exponentZ != exponentX");
        assertEq(signedCoefficientZ, signedCoefficientY, "signedCoefficientZ != signedCoefficientY");
        assertEq(exponentZ, exponentY, "exponentZ != exponentY");
    }

    /// x.min(y) for x < y
    function testMinXYLess(Float x, Float y) external pure {
        vm.assume(x.lt(y));
        Float z = x.min(y);
        assertTrue(z.eq(x), "x.min(y) != x");
        assertTrue(!z.eq(y), "x.min(y) == y");
    }

    /// x.min(y) for x > y
    function testMinXYGreater(Float x, Float y) external pure {
        vm.assume(x.gt(y));
        Float z = x.min(y);
        assertTrue(z.eq(y), "x.min(y) != y");
        assertTrue(!z.eq(x), "x.min(y) == x");
    }
}
