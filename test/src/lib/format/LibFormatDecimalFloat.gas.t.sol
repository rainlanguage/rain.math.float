// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, console2} from "forge-std-1.17.0/src/Test.sol";
import {LibFormatDecimalFloat} from "src/lib/format/LibFormatDecimalFloat.sol";
import {Float, LibDecimalFloat} from "src/lib/LibDecimalFloat.sol";

/// Logs the gas of one `toDecimalString` per Float, for comparison across
/// revisions.
contract LibFormatDecimalFloatGasTest is Test {
    function formatGas(Float float, bool scientific) external view returns (string memory s, uint256 gasUsed) {
        uint256 before = gasleft();
        s = LibFormatDecimalFloat.toDecimalString(float, scientific);
        gasUsed = before - gasleft();
    }

    function check(int256 c, int256 e, bool scientific, string memory expected) internal view {
        (string memory s, uint256 gasUsed) = this.formatGas(LibDecimalFloat.packLossless(c, e), scientific);
        console2.log(expected, scientific, gasUsed);
        assertEq(s, expected);
    }

    function testFormatGasCommon() external view {
        check(0, 0, false, "0");
        check(1, 0, false, "1");
        check(1, 0, true, "1");
        check(15, -1, false, "1.5");
        check(15, -1, true, "1.5");
        check(-123456, -3, false, "-123.456");
        check(-123456, -3, true, "-1.23456e2");
        check(15, -8, false, "0.00000015");
        check(15, -8, true, "1.5e-7");
        check(1, 18, false, "1000000000000000000");
        check(1, 18, true, "1e18");
        check(12, 2, false, "1200");
        check(
            type(int224).max, 0, false, "13479973333575319897333507543509815336818572211270286240551805124607"
        );
        check(
            type(int224).max, 0, true, "1.3479973333575319897333507543509815336818572211270286240551805124607e67"
        );
    }
}
