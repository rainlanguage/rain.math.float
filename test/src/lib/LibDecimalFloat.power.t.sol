// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LogTest} from "../../abstract/LogTest.sol";

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

import {console2} from "forge-std/Test.sol";

contract LibDecimalFloatPowerTest is LogTest {
    using LibDecimalFloat for Float;

    function powerExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        returns (int256, int256)
    {
        return LibDecimalFloat.power(logTables(), signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    function powerExternal(Float floatA, Float floatB) external returns (Float) {
        return LibDecimalFloat.power(logTables(), floatA, floatB);
    }
    /// Stack and mem are the same.

    function testPowerMem(Float a, Float b) external {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        try this.powerExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            Float float = this.powerExternal(a, b);
            (int256 signedCoefficientUnpacked, int256 exponentUnpacked) = float.unpack();
            assertEq(signedCoefficient, signedCoefficientUnpacked);
            assertEq(exponent, exponentUnpacked);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.powerExternal(a, b);
        }
    }

    function checkPower(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal {
        address tables = logTables();
        uint256 a = gasleft();
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloat.power(tables, signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        uint256 b = gasleft();
        console2.log("%d %d Gas used: %d", uint256(signedCoefficientA), uint256(exponentA), a - b);
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signedCoefficient");
        assertEq(actualExponent, expectedExponent, "exponent");
    }

    function testPowers() external {
        checkPower(5e37, -38, 3e37, -36, 9.3283582089552238805970149253731343283e37, -47);
        checkPower(5e37, -38, 6e37, -36, 8.7108013937282229965156794425087108013e37, -56);
    }

    function checkRoundTrip(int256 x, int256 exponentX, int256 y, int256 exponentY) internal {
        address tables = logTables();
        (int256 result, int256 exponent) = LibDecimalFloat.power(tables, x, exponentX, y, exponentY);
        (y, exponentY) = LibDecimalFloat.inv(y, exponentY);
        (int256 roundTrip, int256 roundTripExponent) = LibDecimalFloat.power(tables, result, exponent, y, exponentY);

        (int256 diff, int256 diffExponent) = LibDecimalFloat.divide(x, exponentX, roundTrip, roundTripExponent);
        (diff, diffExponent) = LibDecimalFloat.sub(diff, diffExponent, 1, 0);
        (diff, diffExponent) = LibDecimalFloat.abs(diff, diffExponent);
        console2.log(diff);
        console2.log(diffExponent);
        assertTrue(LibDecimalFloat.lt(diff, diffExponent, 0.0025e4, -4), "diff");
    }

    /// X^Y^(1/Y) = X
    /// Can generally round trip whatever within 1% of the original value.
    function testRoundTrip() external {
        checkRoundTrip(5, 0, 2, 0);
        checkRoundTrip(5, 0, 3, 0);
        checkRoundTrip(50, 0, 40, 0);
        checkRoundTrip(5, -1, 3, -1);
        checkRoundTrip(5, -1, 2, -1);
        checkRoundTrip(5, 100, 3, 20);
        checkRoundTrip(5, -1, 100, 0);
    }
}
