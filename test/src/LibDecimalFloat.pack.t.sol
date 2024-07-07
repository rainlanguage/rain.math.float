// SPDX-License-Identifier: CAL
pragma solidity ^0.8.25;

import {LibDecimalFloat, ExponentOverflow, EXPONENT_MIN, EXPONENT_MAX} from "src/lib/LibDecimalFloat.sol";
import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatPackTest is Test {
    /// Round trip from/to parts.
    function testPartsRoundTrip(int128 signedCoefficient, int128 exponent) external pure {
        uint256 packed = LibDecimalFloat.pack(signedCoefficient, exponent);
        (int256 signedCoefficientOut, int256 exponentOut) = LibDecimalFloat.unpack(packed);

        assertEq(signedCoefficient, signedCoefficientOut, "coefficient");
        assertEq(exponent, exponentOut, "exponent");
    }

    /// Can round trip any normalized number.
    function testNormalizedRoundTrip(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, EXPONENT_MIN, EXPONENT_MAX);
        // This is a special case which will revert the exponent.
        if (signedCoefficient == type(int256).min) {
            vm.assume(exponent != EXPONENT_MAX);
        }
        (signedCoefficient, exponent) = LibDecimalFloat.normalize(signedCoefficient, exponent);

        uint256 packed = LibDecimalFloat.pack(signedCoefficient, exponent);
        (int256 signedCoefficientOut, int256 exponentOut) = LibDecimalFloat.unpack(packed);

        assertEq(signedCoefficient, signedCoefficientOut, "coefficient");
        assertEq(exponent, exponentOut, "exponent");
    }
}
