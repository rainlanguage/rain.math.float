// SPDX-License-Identifier: CAL
pragma solidity ^0.8.25;

import {
    LibDecimalFloat,
    ExponentOverflow,
    EXPONENT_MIN,
    EXPONENT_MAX,
    PackedFloat,
    Float
} from "src/lib/LibDecimalFloat.sol";
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
