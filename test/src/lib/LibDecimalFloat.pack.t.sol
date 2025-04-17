// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, ExponentOverflow, Float, EXPONENT_MAX} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatPackTest is Test {
    function packExternal(int256 signedCoefficient, int256 exponent) external pure returns (Float) {
        return LibDecimalFloat.pack(signedCoefficient, exponent);
    }

    function unpackExternal(Float float) external pure returns (int256, int256) {
        return LibDecimalFloat.unpack(float);
    }

    /// Round trip from/to parts.
    function testPartsRoundTrip(int224 signedCoefficient, int32 exponent) external pure {
        Float float = LibDecimalFloat.pack(signedCoefficient, exponent);
        (int256 signedCoefficientOut, int256 exponentOut) = LibDecimalFloat.unpack(float);

        assertEq(signedCoefficient, signedCoefficientOut, "coefficient");
        if (signedCoefficient != 0) {
            assertEq(exponent, exponentOut, "exponent");
        } else {
            // 0 exponent is always 0.
            assertEq(exponentOut, 0, "exponent");
        }
    }

    /// Can round trip any normalized number provided the exponent is in range.
    function testNormalizedRoundTrip(int256 signedCoefficient, int32 exponent) external pure {
        (int256 signedCoefficientNormalized, int256 exponentNormalized) =
            LibDecimalFloatImplementation.normalize(signedCoefficient, exponent);
        vm.assume(int32(exponentNormalized) == exponentNormalized);

        Float float = LibDecimalFloat.pack(signedCoefficientNormalized, exponentNormalized);
        (int256 signedCoefficientUnpacked, int256 exponentUnpacked) = LibDecimalFloat.unpack(float);

        assertTrue(
            LibDecimalFloat.eq(
                signedCoefficientNormalized, exponentNormalized, signedCoefficientUnpacked, exponentUnpacked
            ),
            "eq"
        );
    }
}
