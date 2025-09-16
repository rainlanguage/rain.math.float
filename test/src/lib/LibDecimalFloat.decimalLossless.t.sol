// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    LibDecimalFloat,
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

    function fromFixedDecimalLosslessPackedExternal(uint256 value, uint8 decimals) external pure returns (Float) {
        return LibDecimalFloat.fromFixedDecimalLosslessPacked(value, decimals);
    }

    function toFixedDecimalLosslessExternal(int256 signedCoefficient, int256 exponent, uint8 decimals)
        external
        pure
        returns (uint256)
    {
        return LibDecimalFloat.toFixedDecimalLossless(signedCoefficient, exponent, decimals);
    }

    function toFixedDecimalLosslessExternal(Float float, uint8 decimals) external pure returns (uint256) {
        return float.toFixedDecimalLossless(decimals);
    }

    function testFromFixedDecimalLosslessMem(uint256 value, uint8 decimals) external {
        value = bound(value, 0, uint256(int256(type(int224).max)));
        (,, bool losslessPreflight) = LibDecimalFloat.fromFixedDecimalLossy(value, decimals);
        if (!losslessPreflight) {
            vm.expectRevert(
                abi.encodeWithSelector(LossyConversionToFloat.selector, value / 10, 1 - int256(uint256(decimals)))
            );
        }
        Float float = LibDecimalFloat.fromFixedDecimalLosslessPacked(value, decimals);
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.fromFixedDecimalLossless(value, decimals);
        (int256 signedCoefficientPacked, int256 exponentPacked) = float.unpack();
        assertEq(signedCoefficient, signedCoefficientPacked);
        assertEq(signedCoefficient == 0 ? int256(0) : exponent, exponentPacked);
    }

    function testToFixedDecimalLosslessPacked(Float float, uint8 decimals) external {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        try this.toFixedDecimalLosslessExternal(signedCoefficient, exponent, decimals) returns (uint256 value) {
            uint256 valueFloat = float.toFixedDecimalLossless(decimals);
            assertEq(valueFloat, value);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            uint256 valueFloat = this.toFixedDecimalLosslessExternal(float, decimals);
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
        this.toFixedDecimalLosslessExternal(1, -1, 0);
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
