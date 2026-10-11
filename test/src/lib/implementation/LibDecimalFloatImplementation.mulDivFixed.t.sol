// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation, POW_FIXED_ONE} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";
import {MulDivOverflow} from "src/error/ErrDecimalFloat.sol";

contract LibDecimalFloatImplementationMulDivFixedTest is Test {
    function check(uint256 x, uint256 y) internal pure {
        assertEq(LibDecimalFloatImplementation.mulDivFixed(x, y), Math.mulDiv(x, y, POW_FIXED_ONE));
    }

    /// A low product word below x y mod 1e50 borrows from the high word.
    function testMulDivFixedRemainderBorrow() external pure {
        // x y = 2^256: the low word is zero and the remainder is not.
        check(2 ** 128, 2 ** 128);
        check(2 ** 255, 2);
        // x y = 2^256 + 2^128: the low word is 2^128, below the remainder.
        check(2 ** 128 + 1, 2 ** 128);
        assertEq(LibDecimalFloatImplementation.mulDivFixed(2 ** 128, 2 ** 128), type(uint256).max / POW_FIXED_ONE);
    }

    function testMulDivFixedMatchesMulDiv(uint256 x, uint256 y) external pure {
        x = bound(x, 0, 2 ** 170);
        y = bound(y, 0, 2 ** 170);
        check(x, y);
    }

    function mulDivFixedExternal(uint256 x, uint256 y) external pure returns (uint256) {
        return LibDecimalFloatImplementation.mulDivFixed(x, y);
    }

    /// #422: mulDivFixed(2^255, 2^255) wrapped to 6.04e76. 2^206 times
    /// 2^50 1e50 is exactly 2^256 1e50, so the quotient is 2^256 and reverts,
    /// and one less in y floors to 2^256 - ceil(2^206 / 1e50), from `bc`.
    function testMulDivFixedQuotientBoundary() external {
        uint256 x = 2 ** 206;
        uint256 y = 2 ** 50 * 1e50;
        uint256 below = 115792089237316195423570985008687907853269984665640564039457584006884689291610;
        assertEq(LibDecimalFloatImplementation.mulDivFixed(x, y - 1), below, "x (y - 1)");
        assertEq(LibDecimalFloatImplementation.mulDivFixed(y - 1, x), below, "(y - 1) x");
        vm.expectRevert(abi.encodeWithSelector(MulDivOverflow.selector, x, y, POW_FIXED_ONE));
        this.mulDivFixedExternal(x, y);
        vm.expectRevert(abi.encodeWithSelector(MulDivOverflow.selector, y, x, POW_FIXED_ONE));
        this.mulDivFixedExternal(y, x);
        // uint256.max times 1 is the largest quotient, and a unit more of y
        // adds uint256.max / 1e50 to it.
        assertEq(LibDecimalFloatImplementation.mulDivFixed(type(uint256).max, POW_FIXED_ONE), type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(MulDivOverflow.selector, type(uint256).max, POW_FIXED_ONE + 1, POW_FIXED_ONE)
        );
        this.mulDivFixedExternal(type(uint256).max, POW_FIXED_ONE + 1);
        vm.expectRevert(abi.encodeWithSelector(MulDivOverflow.selector, 2 ** 255, 2 ** 255, POW_FIXED_ONE));
        this.mulDivFixedExternal(2 ** 255, 2 ** 255);
    }

    /// The quotient fits exactly when x y is below 2^256 1e50, whose high
    /// word is 1e50 and low word zero, so exactly when x y's high word is
    /// below 1e50.
    function testMulDivFixedOverflowFuzz(uint256 x, uint256 y) external {
        (uint256 high,) = Math.mul512(x, y);
        if (high < POW_FIXED_ONE) {
            assertEq(this.mulDivFixedExternal(x, y), Math.mulDiv(x, y, POW_FIXED_ONE));
        } else {
            vm.expectRevert(abi.encodeWithSelector(MulDivOverflow.selector, x, y, POW_FIXED_ONE));
            this.mulDivFixedExternal(x, y);
        }
    }
}
