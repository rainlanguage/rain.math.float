// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibFormatDecimalFloat} from "src/lib/format/LibFormatDecimalFloat.sol";
import {LibParseDecimalFloat} from "src/lib/parse/LibParseDecimalFloat.sol";

/// The `DecimalFloat` ABI over this source, for the Rust bindings' tests.
/// Every function not documented otherwise is the `LibDecimalFloat` function
/// of its name.
contract TestDecimalFloat {
    using LibDecimalFloat for Float;

    /// `LibDecimalFloat.FLOAT_MAX_POSITIVE_VALUE`.
    function maxPositiveValue() external pure returns (Float) {
        return LibDecimalFloat.FLOAT_MAX_POSITIVE_VALUE;
    }

    /// `LibDecimalFloat.FLOAT_MIN_POSITIVE_VALUE`.
    function minPositiveValue() external pure returns (Float) {
        return LibDecimalFloat.FLOAT_MIN_POSITIVE_VALUE;
    }

    /// `LibDecimalFloat.FLOAT_MAX_NEGATIVE_VALUE`.
    function maxNegativeValue() external pure returns (Float) {
        return LibDecimalFloat.FLOAT_MAX_NEGATIVE_VALUE;
    }

    /// `LibDecimalFloat.FLOAT_MIN_NEGATIVE_VALUE`.
    function minNegativeValue() external pure returns (Float) {
        return LibDecimalFloat.FLOAT_MIN_NEGATIVE_VALUE;
    }

    /// `LibDecimalFloat.FLOAT_ZERO`.
    function zero() external pure returns (Float) {
        return LibDecimalFloat.FLOAT_ZERO;
    }

    /// `LibDecimalFloat.FLOAT_E`.
    function e() external pure returns (Float) {
        return LibDecimalFloat.FLOAT_E;
    }

    /// `LibParseDecimalFloat.parseDecimalFloat`.
    function parse(string memory str) external pure returns (bytes4, Float) {
        (bytes4 errorSelector, Float parsed) = LibParseDecimalFloat.parseDecimalFloat(str);
        return (errorSelector, parsed);
    }

    /// `LibFormatDecimalFloat.toDecimalString`.
    function format(Float a, bool scientific) external pure returns (string memory) {
        return LibFormatDecimalFloat.toDecimalString(a, scientific);
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

    function pow10(Float a) external pure returns (Float) {
        return a.pow10();
    }

    function log10(Float a) external pure returns (Float) {
        return a.log10();
    }

    function pow(Float a, Float b) external pure returns (Float) {
        return a.pow(b);
    }

    function sqrt(Float a) external pure returns (Float) {
        return a.sqrt();
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

    /// `LibDecimalFloat.fromFixedDecimalLosslessPacked`.
    function fromFixedDecimalLossless(uint256 value, uint8 decimals) external pure returns (Float) {
        return LibDecimalFloat.fromFixedDecimalLosslessPacked(value, decimals);
    }

    function toFixedDecimalLossless(Float float, uint8 decimals) external pure returns (uint256) {
        return LibDecimalFloat.toFixedDecimalLossless(float, decimals);
    }

    /// `LibDecimalFloat.fromFixedDecimalLossyPacked`.
    function fromFixedDecimalLossy(uint256 value, uint8 decimals) external pure returns (Float, bool) {
        //slither-disable-next-line unused-return
        return LibDecimalFloat.fromFixedDecimalLossyPacked(value, decimals);
    }

    function toFixedDecimalLossy(Float float, uint8 decimals) external pure returns (uint256, bool) {
        //slither-disable-next-line unused-return
        return LibDecimalFloat.toFixedDecimalLossy(float, decimals);
    }
}
