// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibSchoolbookProduct} from "../../../lib/LibSchoolbookProduct.sol";

contract LibDecimalFloatImplementationMul512Test is Test {
    function check(uint256 a, uint256 b, uint256 expectedHigh, uint256 expectedLow) internal pure {
        (uint256 high, uint256 low) = LibDecimalFloatImplementation.mul512(a, b);
        assertEq(high, expectedHigh, "high");
        assertEq(low, expectedLow, "low");
        (high, low) = LibDecimalFloatImplementation.mul512(b, a);
        assertEq(high, expectedHigh, "high commuted");
        assertEq(low, expectedLow, "low commuted");
    }

    function testMul512Boundaries() external pure {
        check(0, type(uint256).max, 0, 0);
        check(1, type(uint256).max, 0, type(uint256).max);
        check(2, type(uint256).max, 1, type(uint256).max - 1);
        check(1 << 128, 1 << 128, 1, 0);
        check(1 << 255, 2, 1, 0);
        check((1 << 128) - 1, (1 << 128) - 1, 0, ((1 << 128) - 1) * ((1 << 128) - 1));
        // The product mod 2^256 - 1 is below the product mod 2^256 here, so
        // the high word borrows.
        check(type(uint256).max, type(uint256).max, type(uint256).max - 1, 1);
    }

    /// Products from `bc`.
    function testMul512Bc() external pure {
        check(
            (1 << 255) + 12345,
            3 ** 150,
            184994242517563486462350391225848322093236550194861486907592202650874124,
            62463552466416740192540923663710148999117002757131412131477243487406646953873
        );
    }

    function testMul512Schoolbook(uint256 a, uint256 b) external pure {
        (uint256 expectedHigh, uint256 expectedLow) = LibSchoolbookProduct.product(a, b);
        check(a, b, expectedHigh, expectedLow);
    }
}
