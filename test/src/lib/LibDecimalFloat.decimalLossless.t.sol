// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    LibDecimalFloat,
    LossyConversionFromFloat,
    LossyConversionToFloat,
    Float
} from "../../../src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";

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

    /// `fromFixedDecimalLosslessPacked(value, 0)` is the bitwise identity
    /// `bytes32(value)` for every `value` that fits in `int224`. Pinned
    /// here so the float library owns the invariant — callers (e.g. the
    /// Rainlang EVM opcodes for `block.number`, `block.timestamp`,
    /// `chainid`) can write the raw integer to the stack as a documented
    /// optimization without re-discovering or re-asserting it.
    function testFromFixedDecimalLosslessPackedZeroDecimalsIsIdentity(uint256 value) external pure {
        value = bound(value, 0, uint256(int256(type(int224).max)));
        Float result = LibDecimalFloat.fromFixedDecimalLosslessPacked(value, 0);
        assertEq(Float.unwrap(result), bytes32(value));
    }

    /// A value that fits int224 converts exactly, so neither path reverts.
    function testFromFixedDecimalLosslessMem(uint256 value, uint8 decimals) external pure {
        value = bound(value, 0, uint256(int256(type(int224).max)));
        Float float = LibDecimalFloat.fromFixedDecimalLosslessPacked(value, decimals);
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.fromFixedDecimalLossless(value, decimals);
        (int256 signedCoefficientPacked, int256 exponentPacked) = float.unpack();
        assertEq(signedCoefficient, signedCoefficientPacked);
        assertEq(signedCoefficient == 0 ? int256(0) : exponent, exponentPacked);
    }

    /// Both paths match the exact `coefficient × 10^(exponent + decimals)`,
    /// with any truncation reverting `LossyConversionFromFloat`.
    function testToFixedDecimalLosslessPacked(Float float, uint8 decimals) external {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        (bytes memory expectedError, uint256 expectedValue, bool lossless) =
            LibTestExactDecimal.toFixedDecimal(signedCoefficient, exponent, decimals);
        if (expectedError.length == 0 && !lossless) {
            expectedError = abi.encodeWithSelector(LossyConversionFromFloat.selector, signedCoefficient, exponent);
        }
        if (expectedError.length > 0) {
            vm.expectRevert(expectedError);
            this.toFixedDecimalLosslessExternal(signedCoefficient, exponent, decimals);
            vm.expectRevert(expectedError);
            this.toFixedDecimalLosslessExternal(float, decimals);
            return;
        }
        assertEq(this.toFixedDecimalLosslessExternal(signedCoefficient, exponent, decimals), expectedValue, "unpacked");
        assertEq(this.toFixedDecimalLosslessExternal(float, decimals), expectedValue, "packed");
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
        assertTrue(signedCoefficient >= 0, "signedCoefficient is negative");
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(uint256(signedCoefficient), value);
        assertEq(exponent, -int256(uint256(decimals)));
    }

    /// Every value that is not exactly a Float reverts LossyConversionToFloat
    /// from the packed conversion with `fromFixedDecimalLossy`'s coefficient
    /// and exponent, whether the digit is lost dividing a value past int256.max
    /// by ten or packing into int224; every other value converts exactly.
    function testFromFixedDecimalLosslessPackedRule(uint256 value, uint8 decimals) external {
        (int256 signedCoefficient, int256 exponent, bool lossless) =
            LibDecimalFloat.fromFixedDecimalLossy(value, decimals);
        (Float expected, bool losslessPack) = LibDecimalFloat.packLossy(signedCoefficient, exponent);
        if (lossless && losslessPack) {
            assertEq(Float.unwrap(this.fromFixedDecimalLosslessPackedExternal(value, decimals)), Float.unwrap(expected));
        } else {
            vm.expectRevert(abi.encodeWithSelector(LossyConversionToFloat.selector, signedCoefficient, exponent));
            this.fromFixedDecimalLosslessPackedExternal(value, decimals);
        }
    }

    function expectLossyPacked(uint256 value, uint8 decimals, int256 signedCoefficient, int256 exponent) internal {
        vm.expectRevert(abi.encodeWithSelector(LossyConversionToFloat.selector, signedCoefficient, exponent));
        this.fromFixedDecimalLosslessPackedExternal(value, decimals);
    }

    /// The packed conversion's boundaries, each exact.
    function testFromFixedDecimalLosslessPackedBoundaries() external {
        int256 int224Max = type(int224).max;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 twiceMax = uint256(type(int256).max) * 2;
        // int224.max fits; one more sheds a non-zero digit packing.
        // forge-lint: disable-next-line(unsafe-typecast)
        this.fromFixedDecimalLosslessPackedExternal(uint256(int224Max), 18);
        // forge-lint: disable-next-line(unsafe-typecast)
        expectLossyPacked(uint256(int224Max + 1), 18, int224Max + 1, -18);
        // Trailing zeros shed exactly.
        // forge-lint: disable-next-line(unsafe-typecast)
        Float shed = this.fromFixedDecimalLosslessPackedExternal(uint256(int224Max * 10), 18);
        (int256 shedCoefficient, int256 shedExponent) = shed.unpack();
        assertEq(shedCoefficient, int224Max, "shed coefficient");
        assertEq(shedExponent, -17, "shed exponent");
        // int256.max has a non-zero digit past int224.
        // forge-lint: disable-next-line(unsafe-typecast)
        expectLossyPacked(uint256(type(int256).max), 6, type(int256).max, -6);
        // Past int256.max: a non-zero last digit is lost dividing by ten.
        // forge-lint: disable-next-line(unsafe-typecast)
        expectLossyPacked(uint256(type(int256).max) + 1, 6, type(int256).min / -10, -5);
        // 2 int256.max ends in 4, lost dividing by ten.
        // forge-lint: disable-next-line(unsafe-typecast)
        expectLossyPacked(twiceMax, 6, type(int256).max / 5, -5);
        // A zero last digit past int256.max: the digit lost is packing's.
        // forge-lint: disable-next-line(unsafe-typecast)
        expectLossyPacked(twiceMax - 4, 6, type(int256).max / 5, -5);
        expectLossyPacked(type(uint256).max, 0, type(int256).max / 5, 1);
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
