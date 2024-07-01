// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat} from "src/lib/LibDecimalFloat.sol";
import {THREES, ONES} from "../lib/LibCommonResults.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatMixedTest is Test {
    /// (1 / 3) * 555e18
    function testDivide1Over3() external pure {
        (int256 signedCoefficientDiv, int256 exponentDiv) = LibDecimalFloat.divide(1, 0, 3, 0);
        assertEq(signedCoefficientDiv, THREES, "coefficient");
        assertEq(exponentDiv, -38, "exponent");

        (int256 signedCoefficientMul, int256 exponentMul) =
            LibDecimalFloat.multiply(signedCoefficientDiv, exponentDiv, 555, 18);

        assertEq(signedCoefficientMul, 18499999999999999999999999999999999999);
        assertEq(exponentMul, -17);
    }
}
