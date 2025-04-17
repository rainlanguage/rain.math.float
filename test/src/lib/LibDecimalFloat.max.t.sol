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

    function maxExternal(Float floatA, Float floatB) external pure returns (Float) {
        return floatA.max(floatB);
    }

    function testMaxMem(Float a, Float b) external {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        try this.maxExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB) returns (
            int256 signedCoefficientResult, int256 exponentResult
        ) {
            Float floatResult = this.maxExternal(a, b);
            (int256 signedCoefficientUnpacked, int256 exponentUnpacked) = floatResult.unpack();
            assertEq(signedCoefficientResult, signedCoefficientUnpacked);
            assertEq(exponentResult, exponentUnpacked);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.maxExternal(a, b);
        }
    }

    /// x.max(x)
    function testMaxX(Float x) external pure {
        Float y = x.max(x);
        assertTrue(y.eq(x), "x.max(x) != x");
    }

    /// x.max(y) == y.max(x)
    function testMaxXY(Float x, Float y) external pure {
        Float maxXY = x.max(y);
        Float maxYX = y.max(x);
        assertTrue(maxXY.eq(maxYX), "maxXY != maxYX");
    }

    /// x.max(y) for x == y
    function testMaxXYEqual(int256 signedCoefficientX, int256 exponentX) external pure {
        int256 signedCoefficientY = signedCoefficientX;
        int256 exponentY = exponentX;
        (int256 signedCoefficientZ, int256 exponentZ) =
            LibDecimalFloat.max(signedCoefficientX, exponentX, signedCoefficientY, exponentY);

        assertEq(signedCoefficientZ, signedCoefficientX, "signedCoefficientZ != signedCoefficientX");
        assertEq(exponentZ, exponentX, "exponentZ != exponentX");
        assertEq(signedCoefficientZ, signedCoefficientY, "signedCoefficientZ != signedCoefficientY");
        assertEq(exponentZ, exponentY, "exponentZ != exponentY");
    }

    /// x.max(y) for x > y
    function testMaxXYGreater(Float x, Float y) external pure {
        vm.assume(x.gt(y));
        Float z = x.max(y);
        assertTrue(z.eq(x), "x.max(y) == x");
        assertTrue(!z.eq(y), "x.max(y) != y");
    }

    /// x.max(y) for x < y
    function testMaxXYLess(Float x, Float y) external pure {
        vm.assume(x.lt(y));
        Float z = x.max(y);
        assertTrue(!z.eq(x), "x.max(y) != x");
        assertTrue(z.eq(y), "x.max(y) == y");
    }
}
