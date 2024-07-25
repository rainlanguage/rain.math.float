// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat} from "src/lib/LibDecimalFloat.sol";

import {Test, console2} from "forge-std/Test.sol";

contract LibDecimalFloatPowerTest is Test {
    function checkPower(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal view {
        uint256 a = gasleft();
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloat.power(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        uint256 b = gasleft();
        console2.log("%d %d Gas used: %d", uint256(signedCoefficientA), uint256(exponentA), a - b);
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signedCoefficient");
        assertEq(actualExponent, expectedExponent, "exponent");
    }

    function testPowers() external view {
        checkPower(5e37, -38, 3e37, -36, 9.3283582089552238805970149253731343283e37, -47);
        checkPower(5e37, -38, 6e37, -36, 8.7108013937282229965156794425087108013e37, -56);
    }

    /// X^Y^(1/Y) = X
    function testRoundTrip(int256 x, int256 exponentX, int256 y, int256 exponentY) external view {
        vm.assume(x > 0);
        vm.assume(y > 0);
        exponentX = bound(exponentX, 1, 10);
        exponentY = bound(exponentY, 1, 10);

        // (int256 result, int256 exponent) = LibDecimalFloat.power(x, exponentX, y, exponentY);
        // (y, exponentY) = LibDecimalFloat.inv(y, exponentY);
        // (int256 roundTrip, int256 roundTripExponent) = LibDecimalFloat.power(result, exponent, y, exponentY);

        // console2.log(x);
        // console2.log(exponentX);
        // console2.log(roundTrip);
        // console2.log(roundTripExponent);

        // (int256 diff, int256 diffExponent) = LibDecimalFloat.sub(x, exponentX, roundTrip, roundTripExponent);
        // (diff, diffExponent) = LibDecimalFloat.abs(diff, diffExponent);

        // assertTrue(LibDecimalFloat.lt(diff, diffExponent, 1, 0), "diff");
    }
}
