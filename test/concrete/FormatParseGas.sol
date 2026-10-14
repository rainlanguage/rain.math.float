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
/// `gasleft()` reads, as `gasUsed`, and the hash of its result as
/// `resultHash`.
contract FormatParseGas {
    /// `toDecimalString` of the #321 copy, `LibFormatDecimalFloatPr321`.
    function formatPr321(Float float, bool scientific) external view returns (uint256 gasUsed, bytes32 resultHash) {
        uint256 gasBefore = gasleft();
        string memory formatted = LibFormatDecimalFloatPr321.toDecimalString(float, scientific);
        gasUsed = gasBefore - gasleft();
        resultHash = keccak256(bytes(formatted));
    }

    /// `toDecimalString` of the live `LibFormatDecimalFloat`.
    function formatLive(Float float, bool scientific) external view returns (uint256 gasUsed, bytes32 resultHash) {
        uint256 gasBefore = gasleft();
        string memory formatted = LibFormatDecimalFloat.toDecimalString(float, scientific);
        gasUsed = gasBefore - gasleft();
        resultHash = keccak256(bytes(formatted));
    }

    /// `toDecimalString` of the plain-Solidity copy,
    /// `LibFormatDecimalFloatSolidity`.
    function formatSol(Float float, bool scientific) external view returns (uint256 gasUsed, bytes32 resultHash) {
        uint256 gasBefore = gasleft();
        string memory formatted = LibFormatDecimalFloatSolidity.toDecimalString(float, scientific);
        gasUsed = gasBefore - gasleft();
        resultHash = keccak256(bytes(formatted));
    }

    /// `parseDecimalFloat` of the #321 copy, `LibParseDecimalFloatPr321`.
    function parsePr321(string memory str) external view returns (uint256 gasUsed, bytes32 resultHash) {
        uint256 gasBefore = gasleft();
        (bytes4 errorSelector, Float parsed) = LibParseDecimalFloatPr321.parseDecimalFloat(str);
        gasUsed = gasBefore - gasleft();
        resultHash = keccak256(abi.encode(errorSelector, parsed));
    }

    /// `parseDecimalFloat` of the live `LibParseDecimalFloat`.
    function parseLive(string memory str) external view returns (uint256 gasUsed, bytes32 resultHash) {
        uint256 gasBefore = gasleft();
        (bytes4 errorSelector, Float parsed) = LibParseDecimalFloat.parseDecimalFloat(str);
        gasUsed = gasBefore - gasleft();
        resultHash = keccak256(abi.encode(errorSelector, parsed));
    }
}
