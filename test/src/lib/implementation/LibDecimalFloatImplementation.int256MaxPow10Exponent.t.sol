// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {INT256_MAX_POW10_EXPONENT} from "../../../../src/lib/implementation/LibDecimalFloatImplementation.sol";

contract LibDecimalFloatImplementationInt256MaxPow10ExponentTest is Test {
    /// `INT256_MAX_POW10_EXPONENT` is the largest k with 10^k in int256, from
    /// 10^76 < 2^255 < 10^77, for both signs.
    function testInt256MaxPow10ExponentDerivation() external pure {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 k = uint256(INT256_MAX_POW10_EXPONENT);
        assertLe(10 ** k, uint256(type(int256).max));
        assertLt(uint256(type(int256).max) / 10 ** k, 10);
        assertLt(uint256(type(int256).max) + 1, 10 ** (k + 1));
    }
}
