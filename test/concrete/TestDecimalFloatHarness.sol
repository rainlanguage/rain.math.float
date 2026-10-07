// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibFormatDecimalFloat} from "src/lib/format/LibFormatDecimalFloat.sol";
import {LibParseDecimalFloat} from "src/lib/parse/LibParseDecimalFloat.sol";

/// The library functions `TestDecimalFloat` does not expose, each by its own
/// name.
contract TestDecimalFloatHarness {
    function packLossy(int256 signedCoefficient, int256 exponent) external pure returns (Float, bool) {
        return LibDecimalFloat.packLossy(signedCoefficient, exponent);
    }

    function packLossless(int256 signedCoefficient, int256 exponent) external pure returns (Float) {
        return LibDecimalFloat.packLossless(signedCoefficient, exponent);
    }

    function packArithmeticResult(int256 signedCoefficient, int256 exponent) external pure returns (Float) {
        return LibDecimalFloat.packArithmeticResult(signedCoefficient, exponent);
    }

    function unpack(Float float) external pure returns (int256, int256) {
        return LibDecimalFloat.unpack(float);
    }

    function canonicalize(Float float) external pure returns (Float) {
        return LibDecimalFloat.canonicalize(float);
    }

    function agree(Float absolute, Float proportional, Float lowest, Float highest) external pure returns (bool) {
        return LibDecimalFloat.agree(absolute, proportional, lowest, highest);
    }

    function isOdd(Float float) external pure returns (bool) {
        return LibDecimalFloat.isOdd(float);
    }

    function fromFixedDecimalLossy(uint256 value, uint8 decimals) external pure returns (int256, int256, bool) {
        return LibDecimalFloat.fromFixedDecimalLossy(value, decimals);
    }

    function fromFixedDecimalLossless(uint256 value, uint8 decimals) external pure returns (int256, int256) {
        return LibDecimalFloat.fromFixedDecimalLossless(value, decimals);
    }

    function toFixedDecimalLossy(int256 signedCoefficient, int256 exponent, uint8 decimals)
        external
        pure
        returns (uint256, bool)
    {
        return LibDecimalFloat.toFixedDecimalLossy(signedCoefficient, exponent, decimals);
    }

    function toFixedDecimalLossless(int256 signedCoefficient, int256 exponent, uint8 decimals)
        external
        pure
        returns (uint256)
    {
        return LibDecimalFloat.toFixedDecimalLossless(signedCoefficient, exponent, decimals);
    }

    function toDecimalString(Float float, bool scientific) external pure returns (string memory) {
        return LibFormatDecimalFloat.toDecimalString(float, scientific);
    }

    function parseDecimalFloat(string memory str) external pure returns (bytes4, Float) {
        return LibParseDecimalFloat.parseDecimalFloat(str);
    }

    /// The cursor is returned as an offset into `str`.
    function parseDecimalFloatInline(string memory str) external pure returns (bytes4, uint256, int256, int256) {
        uint256 start;
        uint256 end;
        assembly ("memory-safe") {
            start := add(str, 0x20)
            end := add(start, mload(str))
        }
        (bytes4 errorSelector, uint256 cursor, int256 signedCoefficient, int256 exponent) =
            LibParseDecimalFloat.parseDecimalFloatInline(start, end);
        return (errorSelector, cursor - start, signedCoefficient, exponent);
    }
}
