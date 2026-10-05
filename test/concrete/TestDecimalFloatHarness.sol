// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibLogTable, ALT_TABLE_FLAG} from "src/lib/table/LibLogTable.sol";

/// The Rust bindings' `TestDecimalFloat` harness ABI over this source:
/// packing, and the log tables as `LibLogTable` ships them.
contract TestDecimalFloatHarness {
    using LibDecimalFloat for Float;

    function packLossless(int224 coefficient, int32 exponent) external pure returns (Float) {
        return LibDecimalFloat.packLossless(coefficient, exponent);
    }

    function unpack(Float float) external pure returns (int256, int256) {
        return LibDecimalFloat.unpack(float);
    }

    function altTableFlag() external pure returns (uint16) {
        return ALT_TABLE_FLAG;
    }

    function logTableDec() external pure returns (uint16[10][90] memory) {
        return LibLogTable.logTableDec();
    }

    function logTableDecSmall() external pure returns (uint8[10][90] memory) {
        return LibLogTable.logTableDecSmall();
    }

    function logTableDecSmallAlt() external pure returns (uint8[10][10] memory) {
        return LibLogTable.logTableDecSmallAlt();
    }

    function antiLogTableDec() external pure returns (uint16[10][100] memory) {
        return LibLogTable.antiLogTableDec();
    }

    function antiLogTableDecSmall() external pure returns (uint8[10][100] memory) {
        return LibLogTable.antiLogTableDecSmall();
    }
}
