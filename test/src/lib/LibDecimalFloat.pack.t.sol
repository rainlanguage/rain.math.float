// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, ExponentOverflow, Float, EXPONENT_MAX} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatPackTest is Test {
    function packLossyExternal(int256 signedCoefficient, int256 exponent) external pure returns (Float, bool) {
        return LibDecimalFloat.packLossy(signedCoefficient, exponent);
    }

    function unpackExternal(Float float) external pure returns (int256, int256) {
        return LibDecimalFloat.unpack(float);
    }

    /// Round trip from/to parts.
    function testPartsRoundTrip(int224 signedCoefficient, int32 exponent) external pure {
        (Float float, bool lossless) = LibDecimalFloat.packLossy(signedCoefficient, exponent);
        (int256 signedCoefficientOut, int256 exponentOut) = LibDecimalFloat.unpack(float);

        assertTrue(lossless, "lossless");
        assertEq(signedCoefficient, signedCoefficientOut, "coefficient");
        assertEq(exponent, exponentOut, "exponent");
    }
}
