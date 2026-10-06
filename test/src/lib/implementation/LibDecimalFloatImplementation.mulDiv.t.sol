// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {MulDivOverflow} from "src/error/ErrDecimalFloat.sol";
import {LibSchoolbookProduct} from "../../../lib/LibSchoolbookProduct.sol";

contract LibDecimalFloatImplementationMulDivTest is Test {
    function mulDivExternal(uint256 x, uint256 y, uint256 denominator) external pure returns (uint256) {
        return LibDecimalFloatImplementation.mulDiv(x, y, denominator);
    }

    /// result is floor(x y / denominator) exactly when result denominator +
    /// (x y mod denominator) is x y, by schoolbook products.
    function assertFloorQuotient(uint256 x, uint256 y, uint256 denominator, uint256 result) internal pure {
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
    }

    function check(uint256 x, uint256 y, uint256 denominator, uint256 expected) internal pure {
        uint256 result = LibDecimalFloatImplementation.mulDiv(x, y, denominator);
        assertEq(result, expected, "mulDiv");
        assertFloorQuotient(x, y, denominator, result);
    }

    function testMulDivSingleWord() external pure {
        check(0, 5, 3, 0);
        check(7, 3, 2, 10);
        check(type(uint256).max, 1, type(uint256).max, 1);
        check(type(uint256).max, 1, 1, type(uint256).max);
    }

    /// Two word products from `bc`: an odd denominator through every Newton
    /// step, with and without the remainder borrowing from the high word, a
    /// power of two, and a power of ten.
    function testMulDivBc() external pure {
        uint256 oddDenominator = 3 ** 161;
        check(
            type(uint256).max,
            oddDenominator - 2,
            oddDenominator,
            115792089237316195423570985008687907853269984665640564039457584007913129639931
        );
        check(
            type(uint256).max,
            oddDenominator - 4,
            oddDenominator,
            115792089237316195423570985008687907853269984665640564039457584007913129639927
        );
        check(type(uint256).max, (1 << 100) + 1, 1 << 200, 91343852333181432387730302044839746322533711871);
        check(
            type(uint256).max,
            9e75,
            1e76,
            104212880313584575881213886507819117067942986199076507635511825607121816675941
        );
        check(type(uint256).max, type(uint256).max, type(uint256).max, type(uint256).max);
    }

    /// A high word equal to the denominator is a quotient of at least 2^256.
    function testMulDivOverflowAtBoundary() external {
        vm.expectRevert(abi.encodeWithSelector(MulDivOverflow.selector, 1 << 128, (1 << 128) + 1, 1));
        this.mulDivExternal(1 << 128, (1 << 128) + 1, 1);
        vm.expectRevert(abi.encodeWithSelector(MulDivOverflow.selector, 1 << 255, 6, 3));
        this.mulDivExternal(1 << 255, 6, 3);
    }

    function testMulDivZeroDenominator() external {
        vm.expectRevert(stdError.divisionError);
        this.mulDivExternal(3, 5, 0);
        vm.expectRevert(abi.encodeWithSelector(MulDivOverflow.selector, type(uint256).max, 2, 0));
        this.mulDivExternal(type(uint256).max, 2, 0);
    }

    function testMulDivSchoolbook(uint256 x, uint256 y, uint256 denominator) external pure {
        (uint256 high,) = LibSchoolbookProduct.product(x, y);
        denominator = bound(denominator, high == 0 ? 1 : high + 1, type(uint256).max);
        assertFloorQuotient(x, y, denominator, LibDecimalFloatImplementation.mulDiv(x, y, denominator));
    }

    function testMulDivOverflow(uint256 x, uint256 y, uint256 denominator) external {
        (uint256 high,) = LibSchoolbookProduct.product(x, y);
        vm.assume(high > 0);
        denominator = bound(denominator, 0, high);
        vm.expectRevert(abi.encodeWithSelector(MulDivOverflow.selector, x, y, denominator));
        this.mulDivExternal(x, y, denominator);
    }
}
