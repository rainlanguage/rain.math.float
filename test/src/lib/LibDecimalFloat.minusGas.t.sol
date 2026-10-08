// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test, console2} from "forge-std-1.17.0/src/Test.sol";

/// Logs the gas of one `minus` and one `abs` per input class, for comparison
/// across revisions. A revert logs the gas of the reverting external call
/// instead.
contract LibDecimalFloatMinusGasTest is Test {
    using LibDecimalFloat for Float;

    function minusGas(Float a) external view returns (Float result, uint256 gasUsed) {
        uint256 before = gasleft();
        result = a.minus();
        gasUsed = before - gasleft();
    }

    function absGas(Float a) external view returns (Float result, uint256 gasUsed) {
        uint256 before = gasleft();
        result = a.abs();
        gasUsed = before - gasleft();
    }

    function measure(string memory name, int256 c, int256 e) internal view {
        Float a = LibDecimalFloat.packLossless(c, e);
        uint256 before = gasleft();
        try this.minusGas(a) returns (Float, uint256 gasUsed) {
            console2.log(string.concat("minus ", name), gasUsed);
        } catch {
            console2.log(string.concat("minus ", name), "reverts, external call gas", before - gasleft());
        }
        before = gasleft();
        try this.absGas(a) returns (Float, uint256 gasUsed) {
            console2.log(string.concat("abs ", name), gasUsed);
        } catch {
            console2.log(string.concat("abs ", name), "reverts, external call gas", before - gasleft());
        }
    }

    function testMinusAbsGas() external view {
        measure("1e0", 1, 0);
        measure("-1e0", -1, 0);
        measure("int224.max e-18", type(int224).max, -18);
        measure("int224.min+1 e-18", type(int224).min + 1, -18);
        measure("0", 0, 0);
        measure("int224.min e0", type(int224).min, 0);
        measure("int224.min int32.min", type(int224).min, type(int32).min);
        measure("int224.min int32.max", type(int224).min, type(int32).max);
    }
}
