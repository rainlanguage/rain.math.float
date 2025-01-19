// SPDX-License-Identifier: CAL
pragma solidity ^0.8.25;

import {LibDecimalFloat, ExponentOverflow, EXPONENT_MIN, EXPONENT_MAX, PackedFloat} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatPackTest is Test {
    /// Round trip from/to parts.
    function testPartsRoundTrip(int128 signedCoefficient, int128 exponent) external pure {
        PackedFloat packed = LibDecimalFloat.pack(signedCoefficient, exponent);
        (int256 signedCoefficientOut, int256 exponentOut) = LibDecimalFloat.unpack(packed);

        assertEq(signedCoefficient, signedCoefficientOut, "coefficient");
        assertEq(exponent, exponentOut, "exponent");
    }

    /// Can round trip any normalized number.
    function testNormalizedRoundTrip(int256 signedCoefficient, int256 exponent) external pure {
        exponent = bound(exponent, EXPONENT_MIN, EXPONENT_MAX);
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.normalize(signedCoefficient, exponent);

        PackedFloat packed = LibDecimalFloat.pack(signedCoefficient, exponent);
        (int256 signedCoefficientOut, int256 exponentOut) = LibDecimalFloat.unpack(packed);

        assertEq(signedCoefficient, signedCoefficientOut, "coefficient");
        assertEq(exponent, exponentOut, "exponent");
    }
}
