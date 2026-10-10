// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float, ExponentOverflow} from "src/lib/LibDecimalFloat.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";
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

    /// Reverts only where the exact difference is beyond the largest Float of
    /// its sign, and otherwise agrees with the unpacked path.
    function testSubPacked(Float a, Float b) external {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        // a - b is a + (-b), and -b of an int224 coefficient is exact in int256.
        if (LibTestExactDecimal.addOverflows(signedCoefficientA, exponentA, -signedCoefficientB, exponentB)) {
            (bool overflowed, int256 signedCoefficientDifference, int256 exponentDifference) =
                LibTestExactDecimal.addPartsWide(signedCoefficientA, exponentA, -signedCoefficientB, exponentB);
            assertFalse(overflowed, "difference past int256 exponent");
            vm.expectRevert(
                abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficientDifference, exponentDifference)
            );
            this.subExternal(a, b);
            return;
        }
        (int256 signedCoefficient, int256 exponent) =
            this.subExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (Float float,) = this.packLossyExternal(signedCoefficient, exponent);
        Float floatImplementation = this.subExternal(a, b);
        assertTrue(float.eq(floatImplementation));
    }

    /// #340: magnitudes cancel, so `1 - 1e-100` rounds away from zero at
    /// `1`'s unit `1e-76`, to `1`. Truncating towards zero would give 67 nines
    /// after the point.
    function testSubRoundingCancelAway() external pure {
        Float difference = LibDecimalFloat.packLossless(1, 0).sub(LibDecimalFloat.packLossless(1, -100));
        assertTrue(difference.eq(LibDecimalFloat.packLossless(1, 0)));
        difference = LibDecimalFloat.packLossless(-1, 0).sub(LibDecimalFloat.packLossless(-1, -100));
        assertTrue(difference.eq(LibDecimalFloat.packLossless(-1, 0)));
    }

    /// #340: `1 - 1.5e-76` rounds away from zero at `1e-76` to `1 - 1e-76`,
    /// then packing truncates that towards zero to 67 nines after the point.
    function testSubRoundingCancelAwayThenPack() external pure {
        Float difference = LibDecimalFloat.packLossless(1, 0).sub(LibDecimalFloat.packLossless(15, -77));
        assertTrue(difference.eq(LibDecimalFloat.packLossless(1e67 - 1, -67)));
    }

    /// #340: magnitudes add, so `1 - (-1e-100)` truncates towards zero.
    function testSubRoundingSameSign() external pure {
        Float difference = LibDecimalFloat.packLossless(1, 0).sub(LibDecimalFloat.packLossless(-1, -100));
        assertTrue(difference.eq(LibDecimalFloat.packLossless(1, 0)));
    }

    /// #332: 0 - int224.min is 2^223, which packs as int224.max at the same
    /// exponent, as `minus` does.
    function testSubZeroInt224Min() external pure {
        Float min = LibDecimalFloat.packLossless(type(int224).min, 0);
        Float difference = LibDecimalFloat.FLOAT_ZERO.sub(min);
        assertEq(Float.unwrap(difference), Float.unwrap(LibDecimalFloat.packLossless(type(int224).max, 0)));
        assertEq(Float.unwrap(difference), Float.unwrap(min.minus()));
    }
}
