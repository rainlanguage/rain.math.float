// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "../../../src/lib/LibDecimalFloat.sol";
import {Test, console2} from "forge-std-1.17.0/src/Test.sol";

/// Logs the gas of one `packLossless` per input class, for comparison across
/// revisions. A revert logs the gas of the reverting external call instead.
contract LibDecimalFloatPackLosslessGasTest is Test {
    function packLosslessGas(int256 c, int256 e) external view returns (Float float, uint256 gasUsed) {
        uint256 before = gasleft();
        float = LibDecimalFloat.packLossless(c, e);
        gasUsed = before - gasleft();
    }

    function measure(string memory name, int256 c, int256 e) internal view {
        uint256 before = gasleft();
        try this.packLosslessGas(c, e) returns (Float, uint256 gasUsed) {
            console2.log(name, gasUsed);
        } catch {
            console2.log(name, "reverts, external call gas", before - gasleft());
        }
    }

    function testPackLosslessGas() external view {
        int256 two223 = int256(1) << 223;
        int256 m = type(int32).max;
        measure("exact 1e0", 1, 0);
        measure("exact int224.max at int32.max", type(int224).max, m);
        measure("lossy shed 1e70 + 1", 1e70 + 1, 0);
        measure("lossy underflow 1 at int32.min - 1", 1, int256(type(int32).min) - 1);
        measure("past max 2^223 at int32.max", two223, m);
        measure("past max (2^223 - 1) * 10 + 9 at int32.max - 1", (two223 - 1) * 10 + 9, m - 1);
        measure("past min -(2^223 + 1) at int32.max", -two223 - 1, m);
        measure("overflow 2^223 + 2 at int32.max", two223 + 2, m);
    }
}
