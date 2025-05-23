// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LogTest} from "../../../abstract/LogTest.sol";

import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

contract LibDecimalFloatImplementationPow10Test is LogTest {
    using LibDecimalFloat for Float;

    function checkPow10(
        int256 signedCoefficient,
        int256 exponent,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal {
        address tables = logTables();
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.pow10(tables, signedCoefficient, exponent);
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signedCoefficient");
        assertEq(actualExponent, expectedExponent, "exponent");
    }

    function testExactPows() external {
        // 10^1 = 10
        checkPow10(1e37, -37, 1000, -2);
        // 10^10 = 10000000000
        checkPow10(10e37, -37, 1000, 7);
        checkPow10(1, 2, 1000, 97);
        checkPow10(1, 3, 1000, 997);
        checkPow10(1, 4, 1000, 9997);
    }

    function testExactLookups() external {
        // 10^2 = 100
        checkPow10(2, 0, 1000, -1);
        // 10^3 = 1000
        checkPow10(3, 0, 1000, 0);
        // 10^4 = 10000
        checkPow10(4, 0, 1000, 1);
        // 10^5 = 100000
        checkPow10(5, 0, 1000, 2);
        // 10^6 = 1000000
        checkPow10(6, 0, 1000, 3);
        // 10^7 = 10000000
        checkPow10(7, 0, 1000, 4);
        // 10^8 = 100000000
        checkPow10(8, 0, 1000, 5);
        // 10^9 = 1000000000
        checkPow10(9, 0, 1000, 6);

        // 10^1.5 = 31.622776601683793319988935444327074859
        checkPow10(1.5e37, -37, 3162, -2);

        checkPow10(0.5e37, -37, 3162, -3);

        checkPow10(0.3e37, -37, 1995, -3);
        checkPow10(-0.3e37, -37, 5.012531328320802005012531328320802005e37, -38);
    }

    function testInterpolatedLookupsPower() external {
        // 10^1.55555 = 35.9376769153
        checkPow10(1.55555e37, -37, 35935e37, -40);
        // 10^1234.56789
        checkPow10(123456789, -5, 36979e37, 1193);
        // ~= 10 (fuzzing found this edge case).
        checkPow10(99999999999999999999999999999999999997448, -41, 99999999999999999999999999999999999991000, -40);
    }

    function boundFloat(int224 x, int32 exponent) internal pure returns (int224, int32) {
        exponent = int32(bound(exponent, -76, 76));
        Float a = LibDecimalFloat.packLossless(x, exponent);
        vm.assume(a.gt(LibDecimalFloat.packLossless(-1e38, 0)));
        vm.assume(a.lt(LibDecimalFloat.packLossless(type(int224).max, 0)));
        return (x, exponent);
    }

    /// Test the current range that we can handle power10 over does not revert.
    function testNoRevert(int224 x, int32 exponent) external {
        (x, exponent) = boundFloat(x, exponent);
        LibDecimalFloatImplementation.pow10(logTables(), x, exponent);
    }
}
