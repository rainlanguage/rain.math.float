// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation, POW_FIXED_ONE} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";

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
}
