// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, EXPONENT_MIN} from "src/lib/LibDecimalFloat.sol";

import {Test, console2} from "forge-std/Test.sol";

contract LibDecimalFloatPower10Test is Test {
    function checkPower10(
        int256 signedCoefficient,
        int256 exponent,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal view {
        uint256 a = gasleft();
        (int256 actualSignedCoefficient, int256 actualExponent) = LibDecimalFloat.power10(signedCoefficient, exponent);
        uint256 b = gasleft();
        console2.log("%d %d Gas used: %d", uint256(signedCoefficient), uint256(exponent), a - b);
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signedCoefficient");
        assertEq(actualExponent, expectedExponent, "exponent");
    }

    function testExactPowers() external view {
        // 10^1 = 10
        checkPower10(1e37, -37, 1000, -2);
        // 10^10 = 10000000000
        checkPower10(10e37, -37, 1000, 7);
        checkPower10(1, 2, 1000, 97);
        checkPower10(1, 3, 1000, 997);
        checkPower10(1, 4, 1000, 9997);
    }

    function testExactLookups() external view {
        // 10^2 = 100
        checkPower10(2, 0, 1000, -1);
        // 10^3 = 1000
        checkPower10(3, 0, 1000, 0);
        // 10^4 = 10000
        checkPower10(4, 0, 1000, 1);
        // 10^5 = 100000
        checkPower10(5, 0, 1000, 2);
        // 10^6 = 1000000
        checkPower10(6, 0, 1000, 3);
        // 10^7 = 10000000
        checkPower10(7, 0, 1000, 4);
        // 10^8 = 100000000
        checkPower10(8, 0, 1000, 5);
        // 10^9 = 1000000000
        checkPower10(9, 0, 1000, 6);

        // 10^1.5 = 31.622776601683793319988935444327074859
        checkPower10(1.5e37, -37, 3162, -2);

        checkPower10(0.5e37, -37, 3162, -3);

        checkPower10(0.3e37, -37, 1995, -3);
        checkPower10(-0.3e37, -37, 5.012531328320802005012531328320802005e37, -38);
    }

    function testInterpolatedLookupsPower() external view {
        // 10^1.55555 = 35.9376769153
        checkPower10(1.55555e37, -37, 35935e37, -40);
        // 10^1234.56789
        checkPower10(123456789, -5, 36979e37, 1193);
    }

    function boundFloat(int256 x, int256 exponent) internal pure returns (int256, int256) {
        exponent = bound(exponent, -76, 76);
        vm.assume(LibDecimalFloat.gt(x, exponent, -1e38, 0));
        vm.assume(LibDecimalFloat.lt(x, exponent, type(int256).max, 0));
        return (x, exponent);
    }

    /// Test the current range that we can handle power10 over does not revert.
    function testNoRevert(int256 x, int256 exponent) external view {
        (x, exponent) = boundFloat(x, exponent);
        LibDecimalFloat.power10(x, exponent);
    }
}
