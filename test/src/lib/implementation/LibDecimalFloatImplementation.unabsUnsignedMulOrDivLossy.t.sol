// SPDX-License-Identifier: CAL
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
            LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(-int256(a), -int256(b), c, exponent);

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
            LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(-int256(a), -int256(b), c, exponent);

        // Expect the result to be negative.
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
            LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(-int256(a), int256(b), c, exponent);

        // Expect the result to be negative.
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
            LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(int256(a), -int256(b), c, exponent);

        // Expect the result to be negative.
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
            LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy(-int256(a), int256(b), c, exponent);

        // Expect the result to be negative.
        int256 expectedSignedCoefficient = -int256(c / 10);
        int256 expectedExponent = exponent + 1;

        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signed coefficient mismatch");
        assertEq(actualExponent, expectedExponent, "exponent mismatch");
    }
}
