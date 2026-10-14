// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {UnabsExponentOverflow} from "src/error/ErrDecimalFloat.sol";

contract LibDecimalFloatImplementationUnabsUnsignedMulOrDivLossyTest is Test {
    function unabsExternal(int256 a, int256 b, uint256 c, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(a, b, c, exponent);
    }

    function expectUnabsExponentOverflow(int256 a, int256 b, uint256 c, int256 exponent) internal {
        vm.expectRevert(abi.encodeWithSelector(UnabsExponentOverflow.selector, a, b, c, exponent));
    }

    /// c = int256.max + 1 is above int256.max, so same-sign operands shed a
    /// digit, and int256.max + 1 is not an int256 exponent.
    function testUnabsExponentOverflowSameSign() external {
        uint256 c = uint256(type(int256).max) + 1;
        expectUnabsExponentOverflow(1, 1, c, type(int256).max);
        this.unabsExternal(1, 1, c, type(int256).max);
        expectUnabsExponentOverflow(-1, -1, c, type(int256).max);
        this.unabsExternal(-1, -1, c, type(int256).max);
    }

    /// c = int256.max + 2 is above |int256.min|, so mixed-sign operands shed a
    /// digit, and int256.max + 1 is not an int256 exponent.
    function testUnabsExponentOverflowMixedSign() external {
        uint256 c = uint256(type(int256).max) + 2;
        expectUnabsExponentOverflow(-1, 1, c, type(int256).max);
        this.unabsExternal(-1, 1, c, type(int256).max);
        expectUnabsExponentOverflow(1, -1, c, type(int256).max);
        this.unabsExternal(1, -1, c, type(int256).max);
    }

    /// 2^255 negated is int256.min, so mixed-sign operands keep it exact at
    /// exponent int256.max.
    function testUnabsMixedSignInt256MinAtExponentMax() external pure {
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(
            -1, 1, uint256(type(int256).max) + 1, type(int256).max
        );
        assertEq(signedCoefficient, type(int256).min);
        assertEq(exponent, type(int256).max);
    }

    /// Every magnitude that sheds at exponent int256.max reverts with the
    /// inputs.
    function testUnabsExponentOverflowAnyShed(int256 a, int256 b, uint256 c) external {
        bool negative = (a < 0) != (b < 0);
        uint256 limit = negative ? uint256(type(int256).max) + 1 : uint256(type(int256).max);
        c = bound(c, limit + 1, type(uint256).max);
        expectUnabsExponentOverflow(a, b, c, type(int256).max);
        this.unabsExternal(a, b, c, type(int256).max);
    }

    /// a and b are both not negative.
    function testUnabsUnsignedMulOrDivLossyPositive(int256 a, int256 b, uint256 c, int256 exponent) external pure {
        a = bound(a, 0, type(int256).max);
        b = bound(b, 0, type(int256).max);
        c = bound(c, 0, uint256(type(int256).max));

        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(a, b, c, exponent);

        // c is range bound so won't truncate when cast.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expectedSignedCoefficient = int256(c);
        int256 expectedExponent = exponent;

        assertEq(actualSignedCoefficient, expectedSignedCoefficient);
        assertEq(actualExponent, expectedExponent);
    }

    /// a and b are both not negative, c overflows int256.
    function testUnabsUnsignedMulOrDivLossyPositiveOverflow(int256 a, int256 b, uint256 c, int256 exponent)
        external
        pure
    {
        a = bound(a, 0, type(int256).max);
        b = bound(b, 0, type(int256).max);
        c = bound(c, uint256(type(int256).max) + 1, type(uint256).max);
        vm.assume(exponent != type(int256).max); // Prevent overflow in exponent.

        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(a, b, c, exponent);
        // Expect the result to be positive.
        // c is divided by 10 before being cast to int256 so won't truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expectedSignedCoefficient = int256(c / 10);
        int256 expectedExponent = exponent + 1;
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signed coefficient mismatch");
        assertEq(actualExponent, expectedExponent, "exponent mismatch");
    }

    /// a and b are both negative.
    function testUnabsUnsignedMulOrDivLossyNegative(int256 a, int256 b, uint256 c, int256 exponent) external pure {
        a = bound(a, type(int256).min, -1);
        b = bound(b, type(int256).min, -1);
        c = bound(c, 0, uint256(type(int256).max));

        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(a, b, c, exponent);

        // c is range bound so won't truncate when cast.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expectedSignedCoefficient = int256(c);
        int256 expectedExponent = exponent;

        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signed coefficient mismatch");
        assertEq(actualExponent, expectedExponent, "exponent mismatch");
    }

    /// a and b are both negative, c overflows int256.
    function testUnabsUnsignedMulOrDivLossyNegativeOverflow(int256 a, int256 b, uint256 c, int256 exponent)
        external
        pure
    {
        a = bound(a, type(int256).min, -1);
        b = bound(b, type(int256).min, -1);
        c = bound(c, uint256(type(int256).max) + 1, type(uint256).max);
        vm.assume(exponent != type(int256).max); // Prevent overflow in exponent.

        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(a, b, c, exponent);

        // Expect the result to be positive.
        // c is divided by 10 before being cast to int256 so won't truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expectedSignedCoefficient = int256(c / 10);
        int256 expectedExponent = exponent + 1;

        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signed coefficient mismatch");
        assertEq(actualExponent, expectedExponent, "exponent mismatch");
    }

    /// a is negative, b is not negative.
    function testUnabsUnsignedMulOrDivLossyMixedAB(int256 a, int256 b, uint256 c, int256 exponent) external pure {
        a = bound(a, type(int256).min, -1);
        b = bound(b, 0, type(int256).max);
        c = bound(c, 0, uint256(type(int256).max));

        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(a, b, c, exponent);

        // Expect the result to be negative.
        // c is range bound so won't truncate when cast.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expectedSignedCoefficient = -int256(c);
        int256 expectedExponent = exponent;

        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signed coefficient mismatch");
        assertEq(actualExponent, expectedExponent, "exponent mismatch");
    }

    /// a is not negative, b is negative. c overflows int256.
    function testUnabsUnsignedMulOrDivLossyMixedBA(int256 a, int256 b, uint256 c, int256 exponent) external pure {
        a = bound(a, 0, type(int256).max);
        b = bound(b, type(int256).min, -1);
        c = bound(c, uint256(type(int256).max) + 2, type(uint256).max);
        vm.assume(exponent != type(int256).max); // Prevent overflow in exponent.

        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(a, b, c, exponent);

        // Expect the result to be negative.
        // c is divided by 10 before being cast to int256 so won't truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expectedSignedCoefficient = -int256(c / 10);
        int256 expectedExponent = exponent + 1;

        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signed coefficient mismatch");
        assertEq(actualExponent, expectedExponent, "exponent mismatch");
    }

    /// a is negative, b is not negative, c overflows int256.
    function testUnabsUnsignedMulOrDivLossyMixedABOverflow(int256 a, int256 b, uint256 c, int256 exponent)
        external
        pure
    {
        a = bound(a, type(int256).min, -1);
        b = bound(b, 0, type(int256).max);
        c = bound(c, uint256(type(int256).max) + 2, type(uint256).max);
        vm.assume(exponent != type(int256).max); // Prevent overflow in exponent.

        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(a, b, c, exponent);

        // Expect the result to be negative.
        // c is divided by 10 before being cast to int256 so won't truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expectedSignedCoefficient = -int256(c / 10);
        int256 expectedExponent = exponent + 1;

        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signed coefficient mismatch");
        assertEq(actualExponent, expectedExponent, "exponent mismatch");
    }

    // c is type(int256).max + 1, a is not negative and b is negative.
    function testUnabsUnsignedMulOrDivLossyMixedBAOverflow(int256 a, int256 b, int256 exponent) external pure {
        a = bound(a, 0, type(int256).max);
        b = bound(b, type(int256).min, -1);
        uint256 c = uint256(type(int256).max) + 1;
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(a, b, c, exponent);
        // Expect the result to be negative.
        int256 expectedSignedCoefficient = type(int256).min;
        int256 expectedExponent = exponent;

        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signed coefficient mismatch");
        assertEq(actualExponent, expectedExponent, "exponent mismatch");
    }

    /// Every input against the rule. The result is negative iff exactly one of
    /// a and b is. A magnitude that fits int256 at that sign is exact at the
    /// exponent. Any other sheds its last digit at exponent + 1, which
    /// overflows only from int256.max.
    function testUnabsUnsignedMulOrDivLossyAnyInput(int256 a, int256 b, uint256 c, int256 exponent) external {
        bool negative = (a < 0) != (b < 0);
        uint256 limit = negative ? uint256(type(int256).max) + 1 : uint256(type(int256).max);
        bool shed = c > limit;
        if (shed && exponent == type(int256).max) {
            expectUnabsExponentOverflow(a, b, c, exponent);
            this.unabsExternal(a, b, c, exponent);
            return;
        }
        (int256 actualSignedCoefficient, int256 actualExponent) = this.unabsExternal(a, b, c, exponent);
        uint256 magnitude = shed ? c / 10 : c;
        assertEq(actualExponent, shed ? exponent + 1 : exponent, "exponent");
        assertEq(actualSignedCoefficient < 0, negative && magnitude != 0, "sign");
        uint256 actualMagnitude;
        if (actualSignedCoefficient == type(int256).min) {
            actualMagnitude = uint256(type(int256).max) + 1;
        } else if (actualSignedCoefficient < 0) {
            // Negating a value above int256.min fits int256.
            // forge-lint: disable-next-line(unsafe-typecast)
            actualMagnitude = uint256(-actualSignedCoefficient);
        } else {
            // Not negative.
            // forge-lint: disable-next-line(unsafe-typecast)
            actualMagnitude = uint256(actualSignedCoefficient);
        }
        assertEq(actualMagnitude, magnitude, "magnitude");
    }
}
