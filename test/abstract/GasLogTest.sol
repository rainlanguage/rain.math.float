// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test, console2} from "forge-std-1.17.0/src/Test.sol";

/// @title GasLogTest
/// @notice Shared logging for the gas tests, which measure inside an external
/// call on themselves so ABI overhead is excluded.
abstract contract GasLogTest is Test {
    /// @notice Logs `name` with the gas the measuring call reports, or with
    /// "reverted" if it reverts.
    /// @param name The label to log.
    /// @param call Calldata for an external view function on this contract
    /// that returns the gas it measured as a `uint256`.
    function logGas(string memory name, bytes memory call) internal view {
        (bool success, bytes memory result) = address(this).staticcall(call);
        if (success) {
            console2.log(name, abi.decode(result, (uint256)));
        } else {
            console2.log(name, "reverted");
        }
    }
}
