// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float, ExponentOverflow} from "../../../src/lib/LibDecimalFloat.sol";
import {LibExactFloat} from "../../lib/LibExactFloat.sol";

import {Test} from "forge-std-1.17.0/src/Test.sol";

contract LibDecimalFloatSubTest is Test {
    using LibDecimalFloat for Float;

    function subExternal(Float floatA, Float floatB) external pure returns (Float) {
        return LibDecimalFloat.sub(floatA, floatB);
    }

    /// The exact counterexample from issue #271. Both operands sit at the
    /// packed exponent floor and the exact difference `-7e-2147483648` is a
    /// Float, so `sub` must return it rather than revert `ExponentUnderflow`.
    function testSubPackedIssue271Counterexample() external view {
        Float a = Float.wrap(0x8000000000000000000000000000000000000000000000000000000000000003);
        Float b = Float.wrap(0x800000000000000000000000000000000000000000000000000000000000000a);

        // The premise: these are 3 and 10 at the exponent floor.
        assertUnpacks(a, 3, type(int32).min, "a");
        assertUnpacks(b, 10, type(int32).min, "b");

        // The symptom in the issue is this call reverting
        // `ExponentUnderflow(-7e75, -2147483723)`.
        assertValue(this.subExternal(a, b), -7, type(int32).min, "difference");

        // And the mirror, so the sign of the result is not what made it work.
        assertValue(this.subExternal(b, a), 7, type(int32).min, "mirror");
    }

    function assertValue(Float float, int256 signedCoefficient, int256 exponent, string memory label) internal pure {
        (int256 signedCoefficientOut, int256 exponentOut) = float.unpack();
        assertEq(LibExactFloat.cmpParts(signedCoefficientOut, exponentOut, signedCoefficient, exponent), 0, label);
    }

    function assertUnpacks(Float float, int256 signedCoefficient, int256 exponent, string memory label) internal pure {
        (int256 signedCoefficientOut, int256 exponentOut) = float.unpack();
        assertEq(signedCoefficientOut, signedCoefficient, string.concat(label, " coefficient"));
        assertEq(exponentOut, exponent, string.concat(label, " exponent"));
    }

    /// Reverts only where the exact difference is beyond the largest Float of
    /// its sign, and otherwise is the documented rounding of the exact sum of
    /// `a` and `-b` (#350).
    function testSubPacked(Float a, Float b) external {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        // a - b is a + (-b), and -b of an int224 coefficient is exact in int256.
        if (LibExactFloat.addOverflows(signedCoefficientA, exponentA, -signedCoefficientB, exponentB)) {
            (bool overflowed, int256 signedCoefficientDifference, int256 exponentDifference) =
                LibExactFloat.addPartsWide(signedCoefficientA, exponentA, -signedCoefficientB, exponentB);
            assertFalse(overflowed, "difference past int256 exponent");
            vm.expectRevert(
                abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficientDifference, exponentDifference)
            );
            this.subExternal(a, b);
            return;
        }
        (int256 signedCoefficient, int256 exponent) = this.subExternal(a, b).unpack();
        assertTrue(
            LibExactFloat.isSumResult(
                signedCoefficientA, exponentA, -signedCoefficientB, exponentB, signedCoefficient, exponent
            ),
            "documented rounding of the exact difference"
        );
    }

    /// `signedCoefficient` within `maxLift` exponents of the int32 floor.
    function nearTheFloor(int224 signedCoefficient, uint256 lift, uint256 maxLift) internal pure returns (Float) {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exponent = int256(type(int32).min) + int256(bound(lift, 0, maxLift));
        return LibDecimalFloat.packLossless(signedCoefficient, exponent);
    }

    /// The documented rounding of the exact difference (#350), from a call
    /// that must not revert.
    function checkSubValue(Float a, Float b) internal view {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (int256 signedCoefficient, int256 exponent) = this.subExternal(a, b).unpack();
        assertTrue(
            LibExactFloat.isSumResult(
                signedCoefficientA, exponentA, -signedCoefficientB, exponentB, signedCoefficient, exponent
            ),
            "documented rounding of the exact difference"
        );
    }

    /// Every Float is a whole multiple of 1e-2147483648, so a difference of
    /// two is zero or at least that in magnitude and `sub` never reverts
    /// `ExponentUnderflow`. `testSubPacked` in both orders with `a` within ten
    /// exponents of the floor and `b` within eighty, where the fuzzer
    /// otherwise never lands.
    function testSubNearTheFloorNeverUnderflows(int224 coefficientA, int224 coefficientB, uint256 liftA, uint256 liftB)
        external
        view
    {
        Float a = nearTheFloor(coefficientA, liftA, 9);
        Float b = nearTheFloor(coefficientB, liftB, 80);
        checkSubValue(a, b);
        checkSubValue(b, a);
    }

    /// #350: magnitudes cancel, and `1 - 1e-100` truncates towards zero to 67
    /// nines after the point.
    function testSubRoundingCancelTowardsZero() external pure {
        Float difference = LibDecimalFloat.packLossless(1, 0).sub(LibDecimalFloat.packLossless(1, -100));
        assertValue(difference, 1e67 - 1, -67, "difference");
        difference = LibDecimalFloat.packLossless(-1, 0).sub(LibDecimalFloat.packLossless(-1, -100));
        assertValue(difference, -(1e67 - 1), -67, "difference");
    }

    /// #350: `1 - 1.5e-76` truncates towards zero to 67 nines after the
    /// point.
    function testSubRoundingCancelPartialDigit() external pure {
        Float difference = LibDecimalFloat.packLossless(1, 0).sub(LibDecimalFloat.packLossless(15, -77));
        assertValue(difference, 1e67 - 1, -67, "difference");
    }

    /// Magnitudes add, so `1 - (-1e-100)` truncates towards zero.
    function testSubRoundingSameSign() external pure {
        Float difference = LibDecimalFloat.packLossless(1, 0).sub(LibDecimalFloat.packLossless(-1, -100));
        assertValue(difference, 1, 0, "difference");
    }

    /// #332: 0 - int224.min is 2^223, which packs as int224.max at the same
    /// exponent, as `minus` does.
    function testSubZeroInt224Min() external pure {
        Float min = LibDecimalFloat.packLossless(type(int224).min, 0);
        Float difference = LibDecimalFloat.FLOAT_ZERO.sub(min);
        assertEq(Float.unwrap(difference), Float.unwrap(LibDecimalFloat.packLossless(type(int224).max, 0)));
        assertEq(Float.unwrap(difference), Float.unwrap(min.minus()));
    }

    /// `b` negates exactly: -(2^223 - 1) - (-2^223) = 1. `minus` packs -b as
    /// 2^223 - 1, so adding it gives -(2^223 - 1) + (2^223 - 1) = 0.
    function testSubInt224MinNegatesExactly() external pure {
        Float a = LibDecimalFloat.packLossless(-type(int224).max, 0);
        Float b = LibDecimalFloat.packLossless(type(int224).min, 0);
        assertValue(a.sub(b), 1, 0, "sub");
        assertValue(a.add(b.minus()), 0, 0, "add minus");
    }
}
