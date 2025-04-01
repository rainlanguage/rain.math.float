// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {
    LibDecimalFloat,
    SIGNED_NORMALIZED_MAX,
    NORMALIZED_MAX,
    LossyConversionFromFloat,
    LossyConversionToFloat,
    Float
} from "../../../src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatDecimalLosslessTest is Test {
    using LibDecimalFloat for Float;

    function fromFixedDecimalLosslessExternal(uint256 value, uint8 decimals) external pure returns (int256, int256) {
        return LibDecimalFloat.fromFixedDecimalLossless(value, decimals);
    }

    function fromFixedDecimalLosslessMemExternal(uint256 value, uint8 decimals) external pure returns (Float memory) {
        return LibDecimalFloat.fromFixedDecimalLosslessMem(value, decimals);
    }

    function toFixedDecimalLosslessExternal(int256 signedCoefficient, int256 exponent, uint8 decimals)
        external
        pure
        returns (uint256)
    {
        return LibDecimalFloat.toFixedDecimalLossless(signedCoefficient, exponent, decimals);
    }

    function toFixedDecimalLosslessMemExternal(Float memory float, uint8 decimals) external pure returns (uint256) {
        return float.toFixedDecimalLossless(decimals);
    }

    /// Memory version of from behaves the same as stack version.
    function testFromFixedDecimalLosslessMem(uint256 value, uint8 decimals) external {
        (,, bool losslessPreflight) = LibDecimalFloat.fromFixedDecimalLossy(value, decimals);
        if (!losslessPreflight) {
            vm.expectRevert(
                abi.encodeWithSelector(LossyConversionToFloat.selector, value / 10, 1 - int256(uint256(decimals)))
            );
        }
        (Float memory float) = LibDecimalFloat.fromFixedDecimalLosslessMem(value, decimals);
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.fromFixedDecimalLossless(value, decimals);
        assertEq(float.signedCoefficient, signedCoefficient);
        assertEq(float.exponent, exponent);
    }

    /// Memory version of to behaves the same as stack version.
    function testToFixedDecimalLosslessMem(Float memory float, uint8 decimals) external {
        try this.toFixedDecimalLosslessExternal(float.signedCoefficient, float.exponent, decimals) returns (
            uint256 value
        ) {
            uint256 valueFloat = float.toFixedDecimalLossless(decimals);
            assertEq(valueFloat, value);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            uint256 valueFloat = this.toFixedDecimalLosslessMemExternal(float, decimals);
            (valueFloat);
        }
    }

    function testToFixedDecimalLosslessPass(int256 signedCoefficient, int256 exponent, uint8 decimals) external pure {
        signedCoefficient = bound(signedCoefficient, 0, 1e18);
        exponent = bound(exponent, 0, 30);
        decimals = uint8(bound(decimals, 0, 18));
        (uint256 expectedResult, bool success) =
            LibDecimalFloat.toFixedDecimalLossy(signedCoefficient, exponent, decimals);
        assertTrue(success, "Lossy conversion failed");

        uint256 result = LibDecimalFloat.toFixedDecimalLossless(signedCoefficient, exponent, decimals);
        assertEq(result, expectedResult, "Lossless conversion failed");
    }

    function testToFixedDecimalLosslessFail() external {
        vm.expectRevert(abi.encodeWithSelector(LossyConversionFromFloat.selector, 1, -1));
        LibDecimalFloat.toFixedDecimalLossless(1, -1, 0);
    }

    function testFromFixedDecimalLosslessPass(uint256 value, uint8 decimals) external pure {
        value = bound(value, 0, uint256(type(int256).max));
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.fromFixedDecimalLossless(value, decimals);
        assertEq(uint256(signedCoefficient), value);
        assertEq(exponent, -int256(uint256(decimals)));
    }

    function testFromFixedDecimalLosslessFail(uint256 value, uint8 decimals) external {
        value = bound(value, uint256(type(int256).max) + 1, type(uint256).max);
        vm.assume(value % 10 != 0);
        vm.expectRevert(
            abi.encodeWithSelector(LossyConversionToFloat.selector, value / 10, 1 - int256(uint256(decimals)))
        );
        this.fromFixedDecimalLosslessExternal(value, decimals);
    }
}
