// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

contract LibDecimalFloatMaxTest is Test {
    using LibDecimalFloat for Float;

    /// x.max(x)
    function testMaxX(Float x) external pure {
        Float y = x.max(x);
        assertTrue(y.eq(x), "x.max(x) != x");
    }

    /// x.max(y) == y.max(x)
    function testMaxXY(Float x, Float y) external pure {
        Float maxXY = x.max(y);
        // forge-lint: disable-next-line(mixed-case-variable)
        Float maxYX = y.max(x);
        assertTrue(maxXY.eq(maxYX), "maxXY != maxYX");
    }

    /// x.max(y) for x == y
    function testMaxXYEqual(Float x) external pure {
        Float y = x;
        Float z = x.max(y);
        assertTrue(z.eq(x), "x.max(y) != x");
        assertTrue(z.eq(y), "x.max(y) != y");
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
