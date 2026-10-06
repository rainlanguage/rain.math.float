// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

contract LibDecimalFloatImplementationRoundSignificantTest is Test {
    /// 41 significant digits, half away from zero, by counting digits, so
    /// independent of `maximize`.
    function expectedRounding(int256 signedCoefficient, int256 exponent) internal pure returns (int256, int256) {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 magnitude = signedCoefficient < 0 ? uint256(-(signedCoefficient + 1)) + 1 : uint256(signedCoefficient);
        uint256 digits = 0;
        for (uint256 rest = magnitude; rest > 0; rest /= 10) {
            digits++;
        }
        if (digits <= 41) {
            return (signedCoefficient, exponent);
        }
        uint256 unit = 10 ** (digits - 41);
        uint256 rounded = magnitude / unit;
        if (2 * (magnitude % unit) >= unit) {
            rounded++;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedRounded = signedCoefficient < 0 ? -int256(rounded) : int256(rounded);
        // forge-lint: disable-next-line(unsafe-typecast)
        return (signedRounded, exponent + int256(digits - 41));
    }

    function check(int256 signedCoefficient, int256 exponent, int256 expectedCoefficient, int256 expectedExponent)
        internal
        pure
    {
        (int256 actualCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.roundSignificant(signedCoefficient, exponent);
        assertEq(actualCoefficient, expectedCoefficient, "coefficient");
        assertEq(actualExponent, expectedExponent, "exponent");
    }

    /// Below 1e41 in magnitude a coefficient is already within 41 digits.
    function testRoundSignificantBelowThreshold() external pure {
        check(0, 7, 0, 7);
        check(1, -3, 1, -3);
        check(1e41 - 1, 5, 1e41 - 1, 5);
        check(-(1e41 - 1), 5, -(1e41 - 1), 5);
    }

    function testRoundSignificantAtThreshold() external pure {
        check(1e41, 0, 1e40, 1);
        check(-1e41, 0, -1e40, 1);
        check(1e41 + 4, -10, 1e40, -9);
        check(-(1e41 + 4), -10, -1e40, -9);
    }

    /// An exact tie rounds away from zero, either sign; one under does not.
    function testRoundSignificantTies() external pure {
        check(1e41 + 5, 0, 1e40 + 1, 1);
        check(-(1e41 + 5), 0, -(1e40 + 1), 1);
        check(999999999999999999999999999999999999999994, 0, 99999999999999999999999999999999999999999, 1);
        check(999999999999999999999999999999999999999995, 0, 1e41, 1);
        check(-999999999999999999999999999999999999999995, 0, -1e41, 1);
        // 76 digits, the guard at 1e35.
        check(
            9876543210987654321098765432109876543210950000000000000000000000000000000000,
            0,
            98765432109876543210987654321098765432110,
            35
        );
        check(
            9876543210987654321098765432109876543210949999999999999999999999999999999999,
            0,
            98765432109876543210987654321098765432109,
            35
        );
        check(
            -9876543210987654321098765432109876543210950000000000000000000000000000000000,
            0,
            -98765432109876543210987654321098765432110,
            35
        );
        check(
            -9876543210987654321098765432109876543210949999999999999999999999999999999999,
            0,
            -98765432109876543210987654321098765432109,
            35
        );
    }

    /// A coefficient that maximizes to 77 digits takes a guard of 1e36 and one
    /// more on the exponent, and rounds the same as one that does not.
    function testRoundSignificantSeventySevenDigits() external pure {
        check(
            12345678901234567890123456789012345678901500000000000000000000000000000000000,
            0,
            12345678901234567890123456789012345678902,
            36
        );
        check(
            12345678901234567890123456789012345678901499999999999999999999999999999999999,
            0,
            12345678901234567890123456789012345678901,
            36
        );
        check(
            -12345678901234567890123456789012345678901500000000000000000000000000000000000,
            0,
            -12345678901234567890123456789012345678902,
            36
        );
        check(type(int256).max, 0, 57896044618658097711785492504343953926635, 36);
        check(type(int256).min, 0, -57896044618658097711785492504343953926635, 36);
        check(type(int256).min + 1, -7, -57896044618658097711785492504343953926635, 29);
        // 42 digits, maximized past 77 digits below 5.79e76 and only to 76
        // digits above it.
        check(123456789012345678901234567890123456789015, 3, 12345678901234567890123456789012345678902, 4);
        check(987654321098765432109876543210987654321095, 3, 98765432109876543210987654321098765432110, 4);
    }

    function testRoundSignificantReference(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, type(int128).min, type(int128).max);
        (int256 expectedCoefficient, int256 expectedExponent) = expectedRounding(signedCoefficient, exponent);
        check(signedCoefficient, exponent, expectedCoefficient, expectedExponent);
    }

    /// The same, weighted onto coefficients of 41 to 43 digits and onto
    /// remainders at the tie.
    function testRoundSignificantReferenceNearTies(uint256 prefix, uint256 digits, int8 offset, bool negative)
        external
        pure
    {
        digits = bound(digits, 42, 77);
        uint256 unit = 10 ** (digits - 41);
        prefix = bound(prefix, 1e40, digits == 77 ? 57896044618658097711785492504343953926634 : 1e41 - 1);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedCoefficient = int256(prefix * unit + unit / 2) + offset;
        if (negative) {
            signedCoefficient = -signedCoefficient;
        }
        (int256 expectedCoefficient, int256 expectedExponent) = expectedRounding(signedCoefficient, -20);
        check(signedCoefficient, -20, expectedCoefficient, expectedExponent);
    }
}
