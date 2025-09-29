// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";

import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

contract LibDecimalFloatImplementationUnabsUnsignedMulOrDivLossyTest is Test {
    /// a and b are both not negative.
    function testUnabsUnsignedMulOrDivLossyPositive(uint256 a, uint256 b, uint256 c, int256 exponent) external pure {
        a = bound(a, 0, uint256(type(int256).max));
        b = bound(b, 0, uint256(type(int256).max));
        c = bound(c, 0, uint256(type(int256).max));

        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(int256(a), int256(b), c, exponent);

        int256 expectedSignedCoefficient = int256(c);
        int256 expectedExponent = exponent;

        assertEq(actualSignedCoefficient, expectedSignedCoefficient);
        assertEq(actualExponent, expectedExponent);
    }

    /// a and b are both not negative, c overflows int256.
    function testUnabsUnsignedMulOrDivLossyPositiveOverflow(uint256 a, uint256 b, uint256 c, int256 exponent)
        external
        pure
    {
        a = bound(a, 0, uint256(type(int256).max));
        b = bound(b, 0, uint256(type(int256).max));
        c = bound(c, uint256(type(int256).max) + 1, type(uint256).max);
        vm.assume(exponent != type(int256).max); // Prevent overflow in exponent.

        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(int256(a), int256(b), c, exponent);
        // Expect the result to be positive.
        // c is divided by 10 before being cast to int256 so won't truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expectedSignedCoefficient = int256(c / 10);
        int256 expectedExponent = exponent + 1;
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signed coefficient mismatch");
        assertEq(actualExponent, expectedExponent, "exponent mismatch");
    }

    /// a and b are both negative.
    function testUnabsUnsignedMulOrDivLossyNegative(uint256 a, uint256 b, uint256 c, int256 exponent) external pure {
        a = bound(a, 1, uint256(type(int256).max));
        b = bound(b, 1, uint256(type(int256).max));
        c = bound(c, 0, uint256(type(int256).max));

        (int256 actualSignedCoefficient, int256 actualExponent) =
        // a and b are both bound to the int256 range.
        // forge-lint: disable-next-line(unsafe-typecast)
         LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(-int256(a), -int256(b), c, exponent);

        // c is range bound so won't truncate when cast.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expectedSignedCoefficient = int256(c);
        int256 expectedExponent = exponent;

        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signed coefficient mismatch");
        assertEq(actualExponent, expectedExponent, "exponent mismatch");
    }

    /// a and b are both negative, c overflows int256.
    function testUnabsUnsignedMulOrDivLossyNegativeOverflow(uint256 a, uint256 b, uint256 c, int256 exponent)
        external
        pure
    {
        a = bound(a, 1, uint256(type(int256).max));
        b = bound(b, 1, uint256(type(int256).max));
        c = bound(c, uint256(type(int256).max) + 1, type(uint256).max);
        vm.assume(exponent != type(int256).max); // Prevent overflow in exponent.

        (int256 actualSignedCoefficient, int256 actualExponent) =
        // a and b are both bound to the int256 range.
        // forge-lint: disable-next-line(unsafe-typecast)
         LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(-int256(a), -int256(b), c, exponent);

        // Expect the result to be positive.
        // c is divided by 10 before being cast to int256 so won't truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expectedSignedCoefficient = int256(c / 10);
        int256 expectedExponent = exponent + 1;

        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signed coefficient mismatch");
        assertEq(actualExponent, expectedExponent, "exponent mismatch");
    }

    /// a is negative, b is positive.
    function testUnabsUnsignedMulOrDivLossyMixedAB(uint256 a, uint256 b, uint256 c, int256 exponent) external pure {
        a = bound(a, 1, uint256(type(int256).max));
        b = bound(b, 0, uint256(type(int256).max));
        c = bound(c, 0, uint256(type(int256).max));

        (int256 actualSignedCoefficient, int256 actualExponent) =
        // a and b are both bound to the int256 range.
        // forge-lint: disable-next-line(unsafe-typecast)
         LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(-int256(a), int256(b), c, exponent);

        // Expect the result to be negative.
        // c is range bound so won't truncate when cast.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expectedSignedCoefficient = -int256(c);
        int256 expectedExponent = exponent;

        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signed coefficient mismatch");
        assertEq(actualExponent, expectedExponent, "exponent mismatch");
    }

    /// a is positive, b is negative. c overflows int256.
    function testUnabsUnsignedMulOrDivLossyMixedBA(uint256 a, uint256 b, uint256 c, int256 exponent) external pure {
        a = bound(a, 0, uint256(type(int256).max));
        b = bound(b, 1, uint256(type(int256).max));
        c = bound(c, uint256(type(int256).max) + 2, type(uint256).max);
        vm.assume(exponent != type(int256).max); // Prevent overflow in exponent.

        (int256 actualSignedCoefficient, int256 actualExponent) =
        // a is in range so won't truncate when cast.
        // b is capped at type(int256).max so won't truncate when cast and can
        // be negated directly.
        // forge-lint: disable-next-line(unsafe-typecast)
         LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(int256(a), -int256(b), c, exponent);

        // Expect the result to be negative.
        // c is divided by 10 before being cast to int256 so won't truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expectedSignedCoefficient = -int256(c / 10);
        int256 expectedExponent = exponent + 1;

        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signed coefficient mismatch");
        assertEq(actualExponent, expectedExponent, "exponent mismatch");
    }

    /// a is negative, b is positive, c overflows int256.
    function testUnabsUnsignedMulOrDivLossyMixedABOverflow(uint256 a, uint256 b, uint256 c, int256 exponent)
        external
        pure
    {
        a = bound(a, 1, uint256(type(int256).max));
        b = bound(b, 0, uint256(type(int256).max));
        c = bound(c, uint256(type(int256).max) + 2, type(uint256).max);
        vm.assume(exponent != type(int256).max); // Prevent overflow in exponent.

        (int256 actualSignedCoefficient, int256 actualExponent) =
        // a and b are both bound to the int256 range.
        // forge-lint: disable-next-line(unsafe-typecast)
         LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(-int256(a), int256(b), c, exponent);

        // Expect the result to be negative.
        // c is divided by 10 before being cast to int256 so won't truncate.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expectedSignedCoefficient = -int256(c / 10);
        int256 expectedExponent = exponent + 1;

        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signed coefficient mismatch");
        assertEq(actualExponent, expectedExponent, "exponent mismatch");
    }

    // c is type(int256).max + 1, a is positive and b is negative.
    function testUnabsUnsignedMulOrDivLossyMixedBAOverflow(uint256 a, uint256 b, int256 exponent) external pure {
        a = bound(a, 1, uint256(type(int256).max));
        b = bound(b, 1, uint256(type(int256).max));
        uint256 c = uint256(type(int256).max) + 1;
        // b is capped at type(int256).max so won't truncate when cast and can
        // be negated directly.
        (int256 actualSignedCoefficient, int256 actualExponent) =
        // forge-lint: disable-next-line(unsafe-typecast)
         LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(int256(a), -int256(b), c, exponent);
        // Expect the result to be negative.
        int256 expectedSignedCoefficient = type(int256).min;
        int256 expectedExponent = exponent;

        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signed coefficient mismatch");
        assertEq(actualExponent, expectedExponent, "exponent mismatch");
    }
}
