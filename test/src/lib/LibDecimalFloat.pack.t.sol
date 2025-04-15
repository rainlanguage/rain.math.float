// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LibDecimalFloat, ExponentOverflow, PackedFloat, Float, EXPONENT_MAX} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatPackTest is Test {
    function packExternal(int256 signedCoefficient, int256 exponent) external pure returns (PackedFloat) {
        return LibDecimalFloat.pack(signedCoefficient, exponent);
    }

    function packExternal(Float memory float) external pure returns (PackedFloat) {
        return LibDecimalFloat.pack(float);
    }

    function unpackExternal(PackedFloat packed) external pure returns (int256, int256) {
        return LibDecimalFloat.unpack(packed);
    }

    function unpackMemExternal(PackedFloat packed) external pure returns (Float memory) {
        return LibDecimalFloat.unpackMem(packed);
    }

    /// Round trip from/to parts.
    function testPartsRoundTrip(int224 signedCoefficient, int32 exponent) external pure {
        PackedFloat packed = LibDecimalFloat.pack(signedCoefficient, exponent);
        (int256 signedCoefficientOut, int256 exponentOut) = LibDecimalFloat.unpack(packed);

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

        PackedFloat packed = LibDecimalFloat.pack(signedCoefficientNormalized, exponentNormalized);
        (int256 signedCoefficientUnpacked, int256 exponentUnpacked) = LibDecimalFloat.unpack(packed);

        assertTrue(
            LibDecimalFloat.eq(
                signedCoefficientNormalized, exponentNormalized, signedCoefficientUnpacked, exponentUnpacked
            ),
            "eq"
        );
    }

    /// Mem and stack versions behave the same for pack.
    function testPackMem(Float memory float) external {
        try this.packExternal(float.signedCoefficient, float.exponent) returns (PackedFloat packed) {
            PackedFloat packedMem = LibDecimalFloat.pack(float);
            assertEq(PackedFloat.unwrap(packed), PackedFloat.unwrap(packedMem), "packed");
        } catch (bytes memory err) {
            vm.expectRevert(err);
            LibDecimalFloat.pack(float);
        }
    }

    /// Mem and stack versions behave the same for unpack.
    function testUnpackMem(PackedFloat packed) external {
        try this.unpackExternal(packed) returns (int256 signedCoefficient, int256 exponent) {
            Float memory float = this.unpackMemExternal(packed);
            assertEq(signedCoefficient, float.signedCoefficient, "coefficient");
            assertEq(exponent, float.exponent, "exponent");
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.unpackMemExternal(packed);
        }
    }
}
