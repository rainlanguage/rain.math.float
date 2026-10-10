// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibFormatDecimalFloat} from "src/lib/format/LibFormatDecimalFloat.sol";
import {LibParseDecimalFloat} from "src/lib/parse/LibParseDecimalFloat.sol";
import {LibFormatDecimalFloatPr321} from "test/lib/LibFormatDecimalFloatPr321.sol";
import {LibParseDecimalFloatPr321} from "test/lib/LibParseDecimalFloatPr321.sol";

contract FormatParseGas {
    function formatBase(Float f, bool scientific) external view returns (uint256 g, bytes32 h) {
        uint256 s = gasleft();
        string memory r = LibFormatDecimalFloatPr321.toDecimalString(f, scientific);
        g = s - gasleft();
        h = keccak256(bytes(r));
    }

    function formatPr(Float f, bool scientific) external view returns (uint256 g, bytes32 h) {
        uint256 s = gasleft();
        string memory r = LibFormatDecimalFloat.toDecimalString(f, scientific);
        g = s - gasleft();
        h = keccak256(bytes(r));
    }

    function parseBase(string memory str) external view returns (uint256 g, bytes32 h) {
        uint256 s = gasleft();
        (bytes4 e, Float f) = LibParseDecimalFloatPr321.parseDecimalFloat(str);
        g = s - gasleft();
        h = keccak256(abi.encode(e, f));
    }

    function parsePr(string memory str) external view returns (uint256 g, bytes32 h) {
        uint256 s = gasleft();
        (bytes4 e, Float f) = LibParseDecimalFloat.parseDecimalFloat(str);
        g = s - gasleft();
        h = keccak256(abi.encode(e, f));
    }
}

/// Gas of `toDecimalString` and `parseDecimalFloat` against their copies from
/// before #310's format and parse changes, measured the same way: the library
/// call alone between two `gasleft()` reads. Every row asserts the same result
/// bytes and no more gas. Run with `forge test --mc
/// LibDecimalFloatFormatParseGasTest -vv`; each line is
