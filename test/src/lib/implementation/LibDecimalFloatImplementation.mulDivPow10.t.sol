// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibSchoolbookProduct} from "../../../lib/LibSchoolbookProduct.sol";

contract LibDecimalFloatImplementationMulDivPow10Test is Test {
    /// result is floor(x y / 10^n) exactly when result 10^n + (x y mod 10^n)
    /// is x y, by schoolbook products, and it equals the generic mulDiv.
    function check(uint256 x, uint256 y, uint256 n) internal pure {
        uint256 result = LibDecimalFloatImplementation.mulDivPow10(x, y, n);
        uint256 denominator = 10 ** n;
        uint256 remainder = mulmod(x, y, denominator);
        (uint256 high, uint256 low) = LibSchoolbookProduct.product(result, denominator);
        uint256 lowWithRemainder;
        unchecked {
            lowWithRemainder = low + remainder;
        }
        if (lowWithRemainder < low) {
            high += 1;
        }
        (uint256 expectedHigh, uint256 expectedLow) = LibSchoolbookProduct.product(x, y);
        assertEq(high, expectedHigh, "high");
        assertEq(lowWithRemainder, expectedLow, "low");
        assertEq(result, LibDecimalFloatImplementation.mulDiv(x, y, denominator), "mulDiv");
    }

    /// Single word products, two word products at both ends of n, and a
    /// remainder that borrows from the high word.
    function testMulDivPow10Examples() external pure {
        check(0, 5, 3);
        check(7, 3, 0);
        check(type(uint256).max, 1, 0);
        check(type(uint256).max, 1, 76);
        check(type(uint256).max, 9e75, 76);
        check(1 << 255, 10, 1);
        check((1 << 255) + 7, 3, 1);
        check(uint224(type(int224).max), uint224(type(int224).max), 58);
        check(14142135623730950488016887242096980785697, 14142135623730950488016887242096980785697, 6);
    }

    /// Every product with a quotient below 2^256: x y at most
    /// 10^n (2^256 - 1).
    function testMulDivPow10Fuzz(uint256 x, uint256 y, uint256 n) external pure {
        n = bound(n, 0, 76);
        if (x > 10 ** n) {
            y = bound(y, 0, LibDecimalFloatImplementation.mulDiv(10 ** n, type(uint256).max, x));
        }
        check(x, y, n);
    }
}
