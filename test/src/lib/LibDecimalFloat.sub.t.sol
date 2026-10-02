// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {Test} from "forge-std-1.17.0/src/Test.sol";

contract LibDecimalFloatSubTest is Test {
    using LibDecimalFloat for Float;

    function subExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (int256, int256)
    {
        return LibDecimalFloatImplementation.sub(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    function subExternal(Float floatA, Float floatB) external pure returns (Float) {
        return LibDecimalFloat.sub(floatA, floatB);
    }

    function packLossyExternal(int256 signedCoefficient, int256 exponent) external pure returns (Float, bool) {
        return LibDecimalFloat.packLossy(signedCoefficient, exponent);
    }

    /// The exact counterexample from issue #271. Both operands sit at the
    /// packed exponent floor, so `add` maximises them to `3e75` and `1e76` at
    /// `-2147483723` and the difference comes back as `-7e75` there. Dropping
    /// the 75 trailing zeros maximisation added is enough to lift the exponent
    /// back to `int32.min` without discarding a significant digit, so the
    /// packed path must produce `-7e-2147483648` exactly as the reference path
    /// does, rather than revert `ExponentUnderflow`.
    function testSubPackedIssue271Counterexample() external view {
        Float a = Float.wrap(0x8000000000000000000000000000000000000000000000000000000000000003);
        Float b = Float.wrap(0x800000000000000000000000000000000000000000000000000000000000000a);

        // The premise: these are 3 and 10 at the exponent floor.
        assertUnpacks(a, 3, type(int32).min, "a");
        assertUnpacks(b, 10, type(int32).min, "b");

        // The packed path: the symptom in the issue is this call reverting
        // `ExponentUnderflow(-7e75, -2147483723)`.
        Float c = this.subExternal(a, b);
        assertUnpacks(c, -7, type(int32).min, "packed");

        // The reference path, as `testSubPacked` runs it: unpacked sub, then
        // packLossy of the result. The result is maximised, so the packing has
        // to shed the trailing zeros to fit the exponent, and that is lossless.
        (int256 signedCoefficient, int256 exponent) = this.subExternal(3, type(int32).min, 10, type(int32).min);
        assertEq(signedCoefficient, -7e75, "reference coefficient");
        assertEq(exponent, int256(type(int32).min) - 75, "reference exponent");
        (Float expected, bool lossless) = this.packLossyExternal(signedCoefficient, exponent);
        assertTrue(lossless, "reference pack lossless");
        assertTrue(c.eq(expected), "packed path disagrees with reference path");

        // And the mirror, so the sign of the result is not what made it work.
        assertUnpacks(this.subExternal(b, a), 7, type(int32).min, "mirror");
    }

    function assertUnpacks(Float float, int256 signedCoefficient, int256 exponent, string memory label) internal pure {
        (int256 signedCoefficientOut, int256 exponentOut) = float.unpack();
        assertEq(signedCoefficientOut, signedCoefficient, string.concat(label, " coefficient"));
        assertEq(exponentOut, exponent, string.concat(label, " exponent"));
    }

    function testSubPacked(Float a, Float b) external {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        try this.subExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB) returns (
            int256 signedCoefficient, int256 exponent
        ) {
            try this.packLossyExternal(signedCoefficient, exponent) returns (Float float, bool lossless) {
                (lossless);
                Float floatImplementation = this.subExternal(a, b);
                assertTrue(float.eq(floatImplementation));
            } catch (bytes memory err) {
                vm.expectRevert(err);
                this.packLossyExternal(signedCoefficient, exponent);
            }
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.subExternal(a, b);
        }
    }
}
