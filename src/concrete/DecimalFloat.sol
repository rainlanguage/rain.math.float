// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "../lib/LibDecimalFloat.sol";
import {LOG_TABLES_ADDRESS} from "../lib/deploy/LibDecimalFloatDeploy.sol";
import {LibFormatDecimalFloat} from "../lib/format/LibFormatDecimalFloat.sol";
import {LibParseDecimalFloat} from "../lib/parse/LibParseDecimalFloat.sol";

contract DecimalFloat {
    using LibDecimalFloat for Float;

    /// Exposes `LibDecimalFloat.FLOAT_MAX_VALUE` for offchain use.
    /// @return The maximum value of a Float.
    function maxValue() external pure returns (Float) {
        return LibDecimalFloat.FLOAT_MAX_VALUE;
    }

    /// Exposes `LibDecimalFloat.FLOAT_MIN_VALUE` for offchain use.
    /// @return The minimum value of a Float.
    function minNegativeValue() external pure returns (Float) {
        return LibDecimalFloat.FLOAT_MIN_NEGATIVE_VALUE;
    }

    /// Exposes `LibDecimalFloat.FLOAT_E` for offchain use.
    /// @return The constant value of Euler's number as a Float.
    function e() external pure returns (Float) {
        return LibDecimalFloat.FLOAT_E;
    }

    /// Exposes `LibParseDecimalFloat.parseDecimalFloat` for offchain use.
    /// @param str The string to parse.
    /// @return errorSelector The selector of the error if parsing failed. `0`
    /// if parsing succeeded.
    /// @return parsed The parsed float. Caller MUST check `errorSelector` to
    /// determine if parsing succeeded.
    function parse(string memory str) external pure returns (bytes4, Float) {
        (bytes4 errorSelector, Float parsed) = LibParseDecimalFloat.parseDecimalFloat(str);
        return (errorSelector, parsed);
    }

    /// Exposes `LibFormatDecimalFloat.toDecimalString` for offchain use.
    /// @param a The float to format.
    /// @return The string representation of the float.
    function format(Float a) external pure returns (string memory) {
        return LibFormatDecimalFloat.toDecimalString(a);
    }

    /// Exposes `LibDecimalFloat.add` for offchain use.
    /// @param a The first float to add.
    /// @param b The second float to add.
    /// @return The sum of the two floats.
    function add(Float a, Float b) external pure returns (Float) {
        return a.add(b);
    }

    /// Exposes `LibDecimalFloat.sub` for offchain use.
    /// @param a The first float to subtract.
    /// @param b The second float to subtract.
    /// @return The difference of the two floats.
    function sub(Float a, Float b) external pure returns (Float) {
        return a.sub(b);
    }

    /// Exposes `LibDecimalFloat.minus` for offchain use.
    /// @param a The float to negate.
    /// @return The negated float.
    function minus(Float a) external pure returns (Float) {
        return a.minus();
    }

    /// Exposes `LibDecimalFloat.abs` for offchain use.
    /// @param a The float to get the absolute value of.
    /// @return The absolute value of the float.
    function abs(Float a) external pure returns (Float) {
        return a.abs();
    }

    /// Exposes `LibDecimalFloat.mul` for offchain use.
    /// @param a The first float to multiply.
    /// @param b The second float to multiply.
    /// @return The product of the two floats.
    function mul(Float a, Float b) external pure returns (Float) {
        return a.mul(b);
    }

    /// Exposes `LibDecimalFloat.div` for offchain use.
    /// @param a The first float to divide.
    /// @param b The second float to divide.
    /// @return The quotient of the two floats.
    function div(Float a, Float b) external pure returns (Float) {
        return a.div(b);
    }

    /// Exposes `LibDecimalFloat.inv` for offchain use.
    /// @param a The float to invert.
    /// @return The inverted float.
    function inv(Float a) external pure returns (Float) {
        return a.inv();
    }

    /// Exposes `LibDecimalFloat.eq` for offchain use.
    /// @param a The first float to compare.
    /// @param b The second float to compare.
    /// @return True if the two floats are equal, false otherwise.
    function eq(Float a, Float b) external pure returns (bool) {
        return a.eq(b);
    }

    /// Exposes `LibDecimalFloat.lt` for offchain use.
    /// @param a The first float to compare.
    /// @param b The second float to compare.
    /// @return True if the first float is less than the second, false otherwise.
    function lt(Float a, Float b) external pure returns (bool) {
        return a.lt(b);
    }

    /// Exposes `LibDecimalFloat.gt` for offchain use.
    /// @param a The first float to compare.
    /// @param b The second float to compare.
    /// @return True if the first float is greater than the second, false
    /// otherwise.
    function gt(Float a, Float b) external pure returns (bool) {
        return a.gt(b);
    }

    /// Exposes `LibDecimalFloat.lte` for offchain use.
    /// @param a The first float to compare.
    /// @param b The second float to compare.
    /// @return True if the first float is less than or equal to the second,
    /// false otherwise.
    function lte(Float a, Float b) external pure returns (bool) {
        return a.lte(b);
    }

    /// Exposes `LibDecimalFloat.gte` for offchain use.
    /// @param a The first float to compare.
    /// @param b The second float to compare.
    /// @return True if the first float is greater than or equal to the second,
    /// false otherwise.
    function gte(Float a, Float b) external pure returns (bool) {
        return a.gte(b);
    }

    /// Exposes `LibDecimalFloat.frac` for offchain use.
    /// @param a The float to get the fractional part of.
    /// @return The fractional part of the float.
    function frac(Float a) external pure returns (Float) {
        return a.frac();
    }

    /// Exposes `LibDecimalFloat.floor` for offchain use.
    /// @param a The float to get the floor of.
    /// @return The floored float.
    function floor(Float a) external pure returns (Float) {
        return a.floor();
    }

    /// Exposes `LibDecimalFloat.pow10` for offchain use.
    /// @param a The float to raise to the power of 10.
    /// @return The result of raising the float to the power of 10.
    function pow10(Float a) external view returns (Float) {
        return a.pow10(LOG_TABLES_ADDRESS);
    }

    /// Exposes `LibDecimalFloat.log10` for offchain use.
    /// @param a The float to take the logarithm of.
    /// @return The logarithm of the float.
    function log10(Float a) external view returns (Float) {
        return a.log10(LOG_TABLES_ADDRESS);
    }

    /// Exposes `LibDecimalFloat.pow` for offchain use.
    /// @param a The base float.
    /// @param b The exponent float.
    /// @return The result of raising the base float to the power of the exponent
    function pow(Float a, Float b) external view returns (Float) {
        return a.pow(b, LOG_TABLES_ADDRESS);
    }

    /// Exposes `LibDecimalFloat.min` for offchain use.
    /// @param a The first float to compare.
    /// @param b The second float to compare.
    /// @return The smaller of the two floats.
    function min(Float a, Float b) external pure returns (Float) {
        return a.min(b);
    }

    /// Exposes `LibDecimalFloat.max` for offchain use.
    /// @param a The first float to compare.
    /// @param b The second float to compare.
    /// @return The larger of the two floats.
    function max(Float a, Float b) external pure returns (Float) {
        return a.max(b);
    }

    /// Exposes `LibDecimalFloat.isZero` for offchain use.
    /// @param a The float to check.
    /// @return True if the float is zero, false otherwise.
    function isZero(Float a) external pure returns (bool) {
        return a.isZero();
    }

    /// Exposes `LibDecimalFloat.packLossless` for offchain use.
    /// @param coefficient The coefficient to pack.
    /// @param exponent The exponent to pack.
    /// @return The packed float.
    function packLossless(int224 coefficient, int32 exponent) external pure returns (Float) {
        return LibDecimalFloat.packLossless(coefficient, exponent);
    }

    /// Exposes `LibDecimalFloat.unpack` for offchain use.
    /// @param float The float to unpack.
    /// @return coefficient The coefficient of the float.
    /// @return exponent The exponent of the float.
    function unpack(Float float) external pure returns (int224, int32) {
        (int256 coefficient, int256 exponent) = LibDecimalFloat.unpack(float);
        return (int224(coefficient), int32(exponent));
    }

    /// Exposes `LibDecimalFloat.fromFixedDecimalLosslessPacked` for offchain
    /// use.
    /// @param value The fixed point decimal value to convert.
    /// @param decimals The number of decimals in the fixed point
    /// representation. e.g. If 1e18 represents 1 this would be 18 decimals.
    /// @return float The Float struct containing the signed coefficient and
    /// exponent.
    function fromFixedDecimalLosslessPacked(uint256 value, uint8 decimals) external pure returns (Float) {
        return LibDecimalFloat.fromFixedDecimalLosslessPacked(value, decimals);
    }

    /// Exposes `LibDecimalFloat.toFixedDecimalLossless` for offchain use.
    /// @param float The Float struct to convert.
    /// @param decimals The number of decimals in the fixed point
    /// representation. e.g. If 1e18 represents 1 this would be 18 decimals.
    /// @return The fixed point decimal value as a uint256.
    function toFixedDecimalLossless(Float float, uint8 decimals) external pure returns (uint256) {
        return LibDecimalFloat.toFixedDecimalLossless(float, decimals);
    }

    /// Exposes `LibDecimalFloat.fromFixedDecimalLossyPacked` for offchain
    /// use.
    /// @param value The fixed point decimal value to convert.
    /// @param decimals The number of decimals in the fixed point
    /// representation. e.g. If 1e18 represents 1 this would be 18 decimals.
    /// @return float The Float struct containing the signed coefficient and
    /// exponent.
    /// @return lossless True if the conversion was lossless, false otherwise.
    function fromFixedDecimalLossyPacked(uint256 value, uint8 decimals) external pure returns (Float, bool) {
        return LibDecimalFloat.fromFixedDecimalLossyPacked(value, decimals);
    }

    /// Exposes `LibDecimalFloat.toFixedDecimalLossy` for offchain use.
    /// @param float The Float struct to convert.
    /// @param decimals The number of decimals in the fixed point
    /// representation. e.g. If 1e18 represents 1 this would be 18 decimals.
    /// @return value The fixed point decimal value as a uint256.
    /// @return lossless True if the conversion was lossless, false otherwise.
    function toFixedDecimalLossy(Float float, uint8 decimals) external pure returns (uint256, bool) {
        return LibDecimalFloat.toFixedDecimalLossy(float, decimals);
    }
}
