// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {DecimalFloat, LibDecimalFloat} from "src/DecimalFloat.sol";

import {Test} from "forge-std/Test.sol";

contract DecimalFloatDivideTest is Test {
    using LibDecimalFloat for DecimalFloat;

    /// 1 / 3
    function testDivide1Over3() external pure {
        DecimalFloat a = LibDecimalFloat.fromParts(1, 0);
        DecimalFloat b = LibDecimalFloat.fromParts(3, 0);
        DecimalFloat actual = a.divide2(b);
        (int256 signedCoefficient, int256 exponent) = actual.toParts();
        assertEq(signedCoefficient, 33333333333333333333333333333333333333, "coefficient");
        assertEq(exponent, -38, "exponent");
    }

    /// - 1 / 3
    function testDivideNegative1Over3() external pure {
        DecimalFloat a = LibDecimalFloat.fromParts(-1, 0);
        DecimalFloat b = LibDecimalFloat.fromParts(3, 0);
        DecimalFloat actual = a.divide2(b);
        (int256 signedCoefficient, int256 exponent) = actual.toParts();
        assertEq(signedCoefficient, -33333333333333333333333333333333333333, "coefficient");
        assertEq(exponent, -38, "exponent");
    }

    /// 1 / 3 gas
    function testDivide1Over3Gas() external pure {
        DecimalFloat.wrap(1).divide2(DecimalFloat.wrap(3));
    }

    /// 1 / 3 gas by parts
    function testDivide1Over3ByPartsGas01() external pure {
        LibDecimalFloat.divideByParts(1, 0, 3, 0);
    }

    /// 1 / 3 gas by parts 10
    function testDivide1Over3ByPartsGas10() external pure {
        (int256 c, int256 e) = LibDecimalFloat.divideByParts(1, 0, 3, 0);
        (c, e) = LibDecimalFloat.divideByParts(e, c, 3, 0);
        (c, e) = LibDecimalFloat.divideByParts(e, c, 3, 0);
        (c, e) = LibDecimalFloat.divideByParts(e, c, 3, 0);
        (c, e) = LibDecimalFloat.divideByParts(e, c, 3, 0);
        (c, e) = LibDecimalFloat.divideByParts(e, c, 3, 0);
        (c, e) = LibDecimalFloat.divideByParts(e, c, 3, 0);
        (c, e) = LibDecimalFloat.divideByParts(e, c, 3, 0);
        (c, e) = LibDecimalFloat.divideByParts(e, c, 3, 0);
        (c, e) = LibDecimalFloat.divideByParts(e, c, 3, 0);
    }

    /// 1e18 / 3
    function testDivide1e18Over3() external pure {
        DecimalFloat.wrap(1e18).divide2(DecimalFloat.wrap(3));
    }
}
