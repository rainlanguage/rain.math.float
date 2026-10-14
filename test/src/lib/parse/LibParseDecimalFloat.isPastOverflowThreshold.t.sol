// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";

import {LibParseDecimalFloat} from "../../../../src/lib/parse/LibParseDecimalFloat.sol";

/// `isPastOverflowThreshold` is total over `(uint256, int256)`, not only over
/// the domain its callers gate it to (#611).
contract LibParseDecimalFloatIsPastOverflowThresholdTest is Test {
    /// `packLossy`'s overflow threshold, `T × 10^int32.max`, has this `T`.
    uint256 constant THRESHOLD_COEFFICIENT = 2 ** 223 + 2;

    /// Whether `magnitude × 10^exponent >= T × 10^int32.max`, by 512-bit
    /// products rather than the library's floor division.
    function referenceIsPast(uint256 magnitude, int256 exponent) internal pure returns (bool) {
        if (magnitude == 0) {
            return false;
        }
        // Past these bounds 10^|excess| alone decides it: 10^68 > T, and
        // 10^78 > 2^256.
        if (exponent > int256(type(int32).max) + 67) {
            return true;
        }
        if (exponent < int256(type(int32).max) - 77) {
            return false;
        }
        int256 excess = exponent - int256(type(int32).max);
        if (excess >= 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            (uint256 high, uint256 low) = Math.mul512(magnitude, 10 ** uint256(excess));
            return high != 0 || low >= THRESHOLD_COEFFICIENT;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        (uint256 tHigh, uint256 tLow) = Math.mul512(THRESHOLD_COEFFICIENT, 10 ** uint256(-excess));
        return tHigh == 0 && magnitude >= tLow;
    }

    function isPastOverflowThresholdExternal(uint256 magnitude, int256 exponent) external pure returns (bool) {
        return LibParseDecimalFloat.isPastOverflowThreshold(magnitude, exponent);
    }

    /// At `int32.max - 10`, `T × 10^10` is past 2^256, so no magnitude is
    /// past the threshold. 5e76 × 10^(int32.max - 10) is 5e66 × 10^int32.max.
    function testIsPastOverflowThresholdTenBelow() external view {
        int256 exponent = int256(type(int32).max) - 10;
        assertFalse(this.isPastOverflowThresholdExternal(5e76, exponent), "5e76");
        assertFalse(this.isPastOverflowThresholdExternal(type(uint256).max, exponent), "uint256.max");
    }

    /// Exponents near int256.min are far below the threshold.
    function testIsPastOverflowThresholdInt256Min() external view {
        assertFalse(this.isPastOverflowThresholdExternal(1, type(int256).min), "1");
        assertFalse(this.isPastOverflowThresholdExternal(type(uint256).max, type(int256).min), "uint256.max");
        assertFalse(this.isPastOverflowThresholdExternal(type(uint256).max, type(int256).min + 1), "min + 1");
    }

    /// Zero is never past the threshold.
    function testIsPastOverflowThresholdZero() external view {
        assertFalse(this.isPastOverflowThresholdExternal(0, int256(type(int32).max) + 68), "+68");
        assertFalse(this.isPastOverflowThresholdExternal(0, type(int256).max), "int256.max");
        assertFalse(this.isPastOverflowThresholdExternal(0, int256(type(int32).max)), "int32.max");
    }

    /// The threshold itself and one below it.
    function testIsPastOverflowThresholdAtThreshold() external view {
        int256 exponent = int256(type(int32).max);
        assertTrue(this.isPastOverflowThresholdExternal(THRESHOLD_COEFFICIENT, exponent), "T");
        assertFalse(this.isPastOverflowThresholdExternal(THRESHOLD_COEFFICIENT - 1, exponent), "T - 1");
        assertTrue(this.isPastOverflowThresholdExternal(THRESHOLD_COEFFICIENT * 1e9, exponent - 9), "T e9");
        assertFalse(this.isPastOverflowThresholdExternal(THRESHOLD_COEFFICIENT * 1e9 - 1, exponent - 9), "T e9 - 1");
    }

    /// Every input agrees with the reference.
    function testIsPastOverflowThresholdFuzz(uint256 magnitude, int256 exponent) external view {
        assertEq(this.isPastOverflowThresholdExternal(magnitude, exponent), referenceIsPast(magnitude, exponent));
    }

    /// Every input near the threshold's exponent agrees with the reference.
    function testIsPastOverflowThresholdNearFuzz(uint256 magnitude, int8 offset) external view {
        int256 exponent = int256(type(int32).max) + int256(offset);
        assertEq(this.isPastOverflowThresholdExternal(magnitude, exponent), referenceIsPast(magnitude, exponent));
    }
}
