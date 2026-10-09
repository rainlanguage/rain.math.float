// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, console2} from "forge-std-1.17.0/src/Test.sol";
import {LibParseDecimalFloat} from "src/lib/parse/LibParseDecimalFloat.sol";
import {Float, LibDecimalFloat} from "src/lib/LibDecimalFloat.sol";

/// Logs the gas of one `parseDecimalFloat` per literal, for comparison across
/// revisions.
contract LibParseDecimalFloatGasTest is Test {
    function parseGas(string memory s) external view returns (bytes4 err, Float float, uint256 gasUsed) {
        uint256 before = gasleft();
        (err, float) = LibParseDecimalFloat.parseDecimalFloat(s);
        gasUsed = before - gasleft();
    }

    function check(string memory s, int256 expectedC, int256 expectedE) internal view {
        (bytes4 err, Float float, uint256 gasUsed) = this.parseGas(s);
        console2.log(s, gasUsed);
        assertEq(err, bytes4(0), "error");
        (int256 c, int256 e) = LibDecimalFloat.unpack(float);
        assertEq(c, expectedC, "coefficient");
        assertEq(e, expectedE, "exponent");
    }

    function testParseGasCommon() external view {
        check("0", 0, 0);
        check("1", 1, 0);
        check("100", 100, 0);
        check("-42", -42, 0);
        check("1.5", 15, -1);
        check("-123.456", -123456, -3);
        check("0.000001", 1, -6);
        check("1e18", 1, 18);
        check("1.5e-7", 15, -8);
        check("1000000000000000000", 1e18, 0);
        check("123456789012345678901234567890.123456789", 123456789012345678901234567890123456789, -9);
    }
}
