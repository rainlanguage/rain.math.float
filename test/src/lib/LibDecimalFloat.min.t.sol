// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

contract LibDecimalFloatMinTest is Test {
    using LibDecimalFloat for Float;

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
    function testMinXYEqual(Float x) external pure {
        Float y = x;
        Float z = x.min(y);
        assertTrue(z.eq(x), "x.min(y) != x");
        assertTrue(z.eq(y), "x.min(y) != y");
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
