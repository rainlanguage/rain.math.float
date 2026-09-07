// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibFormatDecimalFloat} from "src/lib/format/LibFormatDecimalFloat.sol";
import {LibParseDecimalFloat} from "src/lib/parse/LibParseDecimalFloat.sol";
import {ScientificMinNotLessThanMax} from "src/error/ErrDecimalFloat.sol";
import {LibTestLogTables} from "test/lib/LibTestLogTables.sol";

/// The `DecimalFloat` ABI over this source, for the Rust bindings' tests. The
/// constructor deploys the log tables, where the deployed concrete requires
/// them at their Zoltu address.
contract TestDecimalFloat {
    using LibDecimalFloat for Float;

    // slither-disable-next-line too-many-digits
    Float public constant FORMAT_DEFAULT_SCIENTIFIC_MIN =
        Float.wrap(0xfffffffc00000000000000000000000000000000000000000000000000000001);

    // slither-disable-next-line too-many-digits
    Float public constant FORMAT_DEFAULT_SCIENTIFIC_MAX =
        Float.wrap(0x0000000900000000000000000000000000000000000000000000000000000001);

    address immutable I_TABLES;

    constructor() {
        I_TABLES = LibTestLogTables.deploy();
    }

    function maxPositiveValue() external pure returns (Float) {
        return LibDecimalFloat.FLOAT_MAX_POSITIVE_VALUE;
    }

    function minPositiveValue() external pure returns (Float) {
        return LibDecimalFloat.FLOAT_MIN_POSITIVE_VALUE;
    }

    function maxNegativeValue() external pure returns (Float) {
        return LibDecimalFloat.FLOAT_MAX_NEGATIVE_VALUE;
    }

    function minNegativeValue() external pure returns (Float) {
        return LibDecimalFloat.FLOAT_MIN_NEGATIVE_VALUE;
    }

    function zero() external pure returns (Float) {
        return LibDecimalFloat.FLOAT_ZERO;
    }

    function e() external pure returns (Float) {
        return LibDecimalFloat.FLOAT_E;
    }

    function parse(string memory str) external pure returns (bytes4, Float) {
        (bytes4 errorSelector, Float parsed) = LibParseDecimalFloat.parseDecimalFloat(str);
        return (errorSelector, parsed);
    }

    function format(Float a, Float scientificMin, Float scientificMax) public pure returns (string memory) {
        if (!scientificMin.lt(scientificMax)) {
            revert ScientificMinNotLessThanMax(scientificMin, scientificMax);
        }
        Float absA = a.abs();
        return LibFormatDecimalFloat.toDecimalString(a, absA.lt(scientificMin) || absA.gt(scientificMax));
    }

    function format(Float a, bool scientific) external pure returns (string memory) {
        return LibFormatDecimalFloat.toDecimalString(a, scientific);
    }

    function format(Float a) external pure returns (string memory) {
        return format(a, FORMAT_DEFAULT_SCIENTIFIC_MIN, FORMAT_DEFAULT_SCIENTIFIC_MAX);
    }

    function add(Float a, Float b) external pure returns (Float) {
        return a.add(b);
    }

    function sub(Float a, Float b) external pure returns (Float) {
        return a.sub(b);
    }

    function minus(Float a) external pure returns (Float) {
        return a.minus();
    }

    function abs(Float a) external pure returns (Float) {
        return a.abs();
    }

    function mul(Float a, Float b) external pure returns (Float) {
        return a.mul(b);
    }

    function div(Float a, Float b) external pure returns (Float) {
        return a.div(b);
    }

    function inv(Float a) external pure returns (Float) {
        return a.inv();
    }

    function eq(Float a, Float b) external pure returns (bool) {
        return a.eq(b);
    }

    function lt(Float a, Float b) external pure returns (bool) {
        return a.lt(b);
    }

    function gt(Float a, Float b) external pure returns (bool) {
        return a.gt(b);
    }

    function lte(Float a, Float b) external pure returns (bool) {
        return a.lte(b);
    }

    function gte(Float a, Float b) external pure returns (bool) {
        return a.gte(b);
    }

    function integer(Float a) external pure returns (Float) {
        return a.integer();
    }

    function frac(Float a) external pure returns (Float) {
        return a.frac();
    }

    function floor(Float a) external pure returns (Float) {
        return a.floor();
    }

    function ceil(Float a) external pure returns (Float) {
        return a.ceil();
    }

    function pow10(Float a) external view returns (Float) {
        return a.pow10(I_TABLES);
    }

    function log10(Float a) external view returns (Float) {
        return a.log10(I_TABLES);
    }

    function pow(Float a, Float b) external view returns (Float) {
        return a.pow(b, I_TABLES);
    }

    function sqrt(Float a) external view returns (Float) {
        return a.sqrt(I_TABLES);
    }

    function min(Float a, Float b) external pure returns (Float) {
        return a.min(b);
    }

    function max(Float a, Float b) external pure returns (Float) {
        return a.max(b);
    }

    function isZero(Float a) external pure returns (bool) {
        return a.isZero();
    }

    function fromFixedDecimalLossless(uint256 value, uint8 decimals) external pure returns (Float) {
        return LibDecimalFloat.fromFixedDecimalLosslessPacked(value, decimals);
    }

    function toFixedDecimalLossless(Float float, uint8 decimals) external pure returns (uint256) {
        return LibDecimalFloat.toFixedDecimalLossless(float, decimals);
    }

    function fromFixedDecimalLossy(uint256 value, uint8 decimals) external pure returns (Float, bool) {
        //slither-disable-next-line unused-return
        return LibDecimalFloat.fromFixedDecimalLossyPacked(value, decimals);
    }

    function toFixedDecimalLossy(Float float, uint8 decimals) external pure returns (uint256, bool) {
        //slither-disable-next-line unused-return
        return LibDecimalFloat.toFixedDecimalLossy(float, decimals);
    }
}
