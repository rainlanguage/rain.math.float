// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

contract CopyArtifactsTest is Test {
    function _assertCommittedMatches(string memory contractName) internal view {
        string memory live = vm.readFile(string.concat("out/", contractName, ".sol/", contractName, ".json"));
        string memory committed = vm.readFile(string.concat("crates/float/abi/", contractName, ".json"));
        assertEq(
            keccak256(bytes(live)),
            keccak256(bytes(committed)),
            string.concat(contractName, ": run `forge script script/CopyArtifacts.sol` to update the committed artifact")
        );
    }

    function testDecimalFloatArtifactCommitted() external view {
        _assertCommittedMatches("DecimalFloat");
    }

    function testTestDecimalFloatArtifactCommitted() external view {
        _assertCommittedMatches("TestDecimalFloat");
    }
}
