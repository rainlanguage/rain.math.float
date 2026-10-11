// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation, POW_FIXED_ONE} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";
import {LibTestExactDecimal, U512} from "test/lib/LibTestExactDecimal.sol";

contract LibDecimalFloatImplementationMulDivFixedTest is Test {
    /// The result q is the floor of x y / 1e50: q 1e50 <= x y < (q + 1) 1e50.
    function check(uint256 x, uint256 y) internal pure {
        uint256 q = LibDecimalFloatImplementation.mulDivFixed(x, y);
        U512 memory product = LibTestExactDecimal.mul(x, y);
        U512 memory low = LibTestExactDecimal.mul(q, POW_FIXED_ONE);
        assertLe(LibTestExactDecimal.cmp(low, product), 0, "q 1e50 <= x y");
        assertGt(
            LibTestExactDecimal.cmp(LibTestExactDecimal.add(low, LibTestExactDecimal.u512(POW_FIXED_ONE)), product),
            0,
            "x y < (q + 1) 1e50"
        );
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

    /// Every x with every y whose quotient is below 2^256. Past 1e50, y is
    /// bounded to floor((2^256 - 1) 1e50 / x), at most one below the largest
    /// such y.
    function testMulDivFixedIsTheFlooredQuotient(uint256 x, uint256 y) external pure {
        if (x > POW_FIXED_ONE) {
            y = bound(y, 0, Math.mulDiv(type(uint256).max, POW_FIXED_ONE, x));
        }
        check(x, y);
    }
}
