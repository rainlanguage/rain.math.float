// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Float} from "../../src/lib/LibDecimalFloat.sol";
import {LibFormatDecimalFloat} from "../../src/lib/format/LibFormatDecimalFloat.sol";
import {LibFormatDecimalFloatSolidity} from "../lib/LibFormatDecimalFloatSolidity.sol";

/// Each function returns the gas of one format call alone, between two
/// `gasleft()` reads, as `gasUsed`, and the hash of its result as
/// `resultHash`.
contract FormatGas {
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
}
