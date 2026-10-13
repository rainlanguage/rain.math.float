// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Test, console2} from "forge-std-1.17.0/src/Test.sol";

/// Logs the gas of `div` per input, measured inside the call so ABI overhead
/// is excluded. Run with `-vv` on two trees to compare them.
contract LibDecimalFloatImplementationDivGasTest is Test {
    function implGas(int256 a, int256 ea, int256 b, int256 eb) external view returns (uint256 g) {
        g = gasleft();
        LibDecimalFloatImplementation.div(a, ea, b, eb);
        g -= gasleft();
    }

    function logImpl(string memory name, int256 a, int256 ea, int256 b, int256 eb) internal view {
        try this.implGas(a, ea, b, eb) returns (uint256 g) {
            console2.log(name, g);
        } catch {
            console2.log(name, "reverted");
        }
    }

    function testDivGas() external view {
        int256 min = type(int256).min;
        int256 max = type(int256).max;
        logImpl("1e0 / 3e0", 1, 0, 3, 0);
        logImpl("15e-1 / 1234567890123456789e-18", 15, -1, 1234567890123456789, -18);
        logImpl("int224.max / -7e5", type(int224).max, 0, -7, 5);
        logImpl("int224.min e(int32.min) / 3e(int32.max)", type(int224).min, type(int32).min, 3, type(int32).max);
        logImpl("spill 1e76e(min) / 3e75e(max-100)", 1e76, min, 3e75, max - 100);
        logImpl("spill overflow 1e76e(min) / 3e75e(max)", 1e76, min, 3e75, max);
        logImpl("spill overflow 1e(min) / 3e76e(max-100)", 1, min, 3e76, max - 100);
    }
}
