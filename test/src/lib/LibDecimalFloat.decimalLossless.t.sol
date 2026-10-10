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
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 expectedResult = uint256(signedCoefficient) * 10 ** (uint256(exponent) + decimals);

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

    /// `value × 10^-decimals` is exactly a Float iff stripping its trailing
    /// zeros leaves an int224 coefficient, as the exponent is always in range.
    /// An exact value packs `value` with the fewest digits shed that fit
    /// int224, zero as `FLOAT_ZERO`. Any other value reverts
    /// LossyConversionToFloat with `fromFixedDecimalLossy`'s parts: `value` at
    /// `-decimals`, or past int256.max, `value / 10` at `1 - decimals`.
    function checkFromFixedDecimalLosslessPackedRule(uint256 value, uint8 decimals) internal {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 int224Max = uint256(int256(type(int224).max));
        uint256 stripped = value;
        while (stripped != 0 && stripped % 10 == 0) {
            stripped /= 10;
        }
        if (stripped <= int224Max) {
            uint256 coefficient = value;
            int256 exponent = -int256(uint256(decimals));
            while (coefficient > int224Max) {
                coefficient /= 10;
                exponent++;
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes32 expected = coefficient == 0 ? bytes32(0) : bytes32(uint256(exponent) << 224 | coefficient);
            assertEq(Float.unwrap(this.fromFixedDecimalLosslessPackedExternal(value, decimals)), expected);
        } else {
            // forge-lint: disable-next-line(unsafe-typecast)
            bool past = value > uint256(type(int256).max);
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 signedCoefficient = past ? int256(value / 10) : int256(value);
            int256 exponent = (past ? int256(1) : int256(0)) - int256(uint256(decimals));
            vm.expectRevert(abi.encodeWithSelector(LossyConversionToFloat.selector, signedCoefficient, exponent));
            this.fromFixedDecimalLosslessPackedExternal(value, decimals);
        }
    }

    function testFromFixedDecimalLosslessPackedRule(uint256 value, uint8 decimals) external {
        checkFromFixedDecimalLosslessPackedRule(value, decimals);
    }

    /// The rule at each boundary, which fuzzing hits only by chance.
    function testFromFixedDecimalLosslessPackedRuleBoundaries() external {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 int224Max = uint256(int256(type(int224).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 int256Max = uint256(type(int256).max);
        uint256[9] memory values = [
            0,
            1,
            int224Max,
            int224Max + 1,
            int224Max * 10,
            int256Max,
            int256Max + 1,
            int256Max / 10 * 10 + 10,
            type(uint256).max
        ];
        uint8[3] memory decimalsList = [0, 18, 255];
        for (uint256 i = 0; i < values.length; i++) {
            for (uint256 j = 0; j < decimalsList.length; j++) {
                checkFromFixedDecimalLosslessPackedRule(values[i], decimalsList[j]);
            }
        }
    }

    /// Uniform values almost never end in zeros, so this also fuzzes
    /// `m × 10^z`, where the exact values past int224 are.
    function testFromFixedDecimalLosslessPackedRuleTrailingZeros(uint256 m, uint256 z, uint8 decimals) external {
        z = bound(z, 0, 77);
        m = bound(m, 0, type(uint256).max / 10 ** z);
        checkFromFixedDecimalLosslessPackedRule(m * 10 ** z, decimals);
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
