// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";

contract CopyArtifacts is Script {
    function run() external {
        _copyArtifact("DecimalFloat");
        _copyArtifact("TestDecimalFloat");
    }

    function _copyArtifact(string memory contractName) internal {
        string memory src = string.concat("out/", contractName, ".sol/", contractName, ".json");
        string memory dst = string.concat("crates/float/abi/", contractName, ".json");
        string memory contents = vm.readFile(src);
        if (vm.exists(dst)) {
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.removeFile(dst);
        }
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(dst, contents);
    }
}
