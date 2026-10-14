// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "../../src/lib/LibDecimalFloat.sol";
import {LibFormatDecimalFloat} from "../../src/lib/format/LibFormatDecimalFloat.sol";
import {LibParseDecimalFloat} from "../../src/lib/parse/LibParseDecimalFloat.sol";
import {LibFormatDecimalFloatPr321} from "../lib/LibFormatDecimalFloatPr321.sol";
import {LibParseDecimalFloatPr321} from "../lib/LibParseDecimalFloatPr321.sol";
import {LibFormatDecimalFloatSolidity} from "../lib/LibFormatDecimalFloatSolidity.sol";

/// Each function returns the gas of one format or parse call alone, between two
/// `gasleft()` reads, as `g`, and the hash of its result as `h`.
contract FormatParseGas {
    /// `toDecimalString` of the #321 copy, `LibFormatDecimalFloatPr321`.
    function formatPr321(Float f, bool scientific) external view returns (uint256 g, bytes32 h) {
        uint256 s = gasleft();
        string memory r = LibFormatDecimalFloatPr321.toDecimalString(f, scientific);
        g = s - gasleft();
        h = keccak256(bytes(r));
    }

    /// `toDecimalString` of the live `LibFormatDecimalFloat`.
    function formatLive(Float f, bool scientific) external view returns (uint256 g, bytes32 h) {
        uint256 s = gasleft();
        string memory r = LibFormatDecimalFloat.toDecimalString(f, scientific);
        g = s - gasleft();
        h = keccak256(bytes(r));
    }

    /// `toDecimalString` of the plain-Solidity copy,
    /// `LibFormatDecimalFloatSolidity`.
    function formatSol(Float f, bool scientific) external view returns (uint256 g, bytes32 h) {
        uint256 s = gasleft();
        string memory r = LibFormatDecimalFloatSolidity.toDecimalString(f, scientific);
        g = s - gasleft();
        h = keccak256(bytes(r));
    }

    /// `parseDecimalFloat` of the #321 copy, `LibParseDecimalFloatPr321`.
    function parsePr321(string memory str) external view returns (uint256 g, bytes32 h) {
        uint256 s = gasleft();
        (bytes4 e, Float f) = LibParseDecimalFloatPr321.parseDecimalFloat(str);
        g = s - gasleft();
        h = keccak256(abi.encode(e, f));
    }

    /// `parseDecimalFloat` of the live `LibParseDecimalFloat`.
    function parseLive(string memory str) external view returns (uint256 g, bytes32 h) {
        uint256 s = gasleft();
        (bytes4 e, Float f) = LibParseDecimalFloat.parseDecimalFloat(str);
        g = s - gasleft();
        h = keccak256(abi.encode(e, f));
    }
}
