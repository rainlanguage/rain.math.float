// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {THREES, ONES} from "../../lib/LibCommonResults.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatMixedTest is Test {
    using LibDecimalFloat for Float;

    /// (1 / 3) * 555e18
    function testDiv1Over3() external pure {
        Float a = LibDecimalFloat.packLossless(1, 0);
        Float b = LibDecimalFloat.packLossless(3, 0);
        Float c = a.div(b);
        (int256 signedCoefficientDiv, int256 exponentDiv) = LibDecimalFloat.unpack(c);
        assertEq(signedCoefficientDiv, THREES, "coefficient");
        assertEq(exponentDiv, -38, "exponent");

        Float d = c.mul(LibDecimalFloat.packLossless(555, 18));
        (int256 signedCoefficientMul, int256 exponentMul) = LibDecimalFloat.unpack(d);

        assertEq(signedCoefficientMul, 18499999999999999999999999999999999999815);
        assertEq(exponentMul, -20);
    }
}
