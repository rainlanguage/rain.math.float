// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

// Re-export console2 here for convenience.
// forge-lint: disable-next-line(unused-import)
import {Test, console2} from "forge-std-1.16.1/src/Test.sol";
import {LibTestLogTables} from "test/lib/LibTestLogTables.sol";

abstract contract LogTest is Test {
    address sTables;

    function logTables() internal returns (address) {
        if (sTables == address(0)) {
            sTables = LibTestLogTables.deploy();
        }
        return sTables;
    }
}
