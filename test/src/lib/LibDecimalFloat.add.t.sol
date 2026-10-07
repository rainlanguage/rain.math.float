// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float, ExponentOverflow} from "src/lib/LibDecimalFloat.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {Test} from "forge-std-1.17.0/src/Test.sol";

contract LibDecimalFloatDecimalAddTest is Test {
    using LibDecimalFloat for Float;

    function addExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (Float)
    {
        (int256 signedCoefficientC, int256 exponentC) =
            LibDecimalFloatImplementation.add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        Float c = LibDecimalFloat.packArithmeticResult(signedCoefficientC, exponentC);
        return c;
    }

    function addExternal(Float a, Float b) external pure returns (Float) {
        return LibDecimalFloat.add(a, b);
    }

    /// The documented rounding of the exact sum (#340).
    function checkAddValue(Float a, Float b, Float result) internal pure {
        (int256 signedCoefficientA, int256 exponentA) = LibDecimalFloat.unpack(a);
        (int256 signedCoefficientB, int256 exponentB) = LibDecimalFloat.unpack(b);
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.unpack(result);
        assertTrue(
            LibTestExactDecimal.isSumResult(
                signedCoefficientA, exponentA, signedCoefficientB, exponentB, signedCoefficient, exponent
            ),
            "documented rounding of the exact sum"
        );
    }

    /// Reverts only where the exact sum is beyond the largest Float of its
    /// sign, otherwise is the documented rounding of the exact sum (#340),
    /// and agrees with the unpacked path.
    function testAddPacked(Float a, Float b) external {
        (int256 signedCoefficientA, int256 exponentA) = LibDecimalFloat.unpack(a);
        (int256 signedCoefficientB, int256 exponentB) = LibDecimalFloat.unpack(b);
        if (LibTestExactDecimal.addOverflows(signedCoefficientA, exponentA, signedCoefficientB, exponentB)) {
            (int256 signedCoefficientSum, int256 exponentSum) =
                LibTestExactDecimal.addPayload(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
            vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficientSum, exponentSum));
            this.addExternal(a, b);
            return;
        }
        Float resultParts = this.addExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.unpack(resultParts);
        Float result = this.addExternal(a, b);
        checkAddValue(a, b, result);
        (int256 signedCoefficientUnpacked, int256 exponentUnpacked) = LibDecimalFloat.unpack(result);
        assertEq(signedCoefficient, signedCoefficientUnpacked);
        assertEq(exponent, exponentUnpacked);
    }

    /// #340: where the magnitudes cancel, the result is either Float adjacent
    /// to the exact sum. `1e100 - 1` lands away from zero on `1e100`. In
    /// `1e76 - 1000000001.5`, truncating the smaller operand gives
    /// `1e76 - 1000000001`, which packing truncates to `(10^67 - 2)e9`, below
    /// the exact sum in magnitude.
    function testAddCancelEitherAdjacentFloat() external pure {
        Float away = LibDecimalFloat.packLossless(1, 100).add(LibDecimalFloat.packLossless(-1, 0));
        assertTrue(away.eq(LibDecimalFloat.packLossless(1, 100)), "away from zero");
        assertTrue(LibTestExactDecimal.isSumResult(1, 100, -1, 0, 1, 100), "away accepted");

        Float toward = LibDecimalFloat.packLossless(1e66, 10).add(LibDecimalFloat.packLossless(-10000000015, -1));
        assertTrue(toward.eq(LibDecimalFloat.packLossless(1e67 - 2, 9)), "towards zero");
        assertTrue(LibTestExactDecimal.isSumResult(1e66, 10, -10000000015, -1, 1e67 - 2, 9), "towards accepted");
        assertFalse(LibTestExactDecimal.isSumResult(1e66, 10, -10000000015, -1, 1e67 - 3, 9), "two below");
        assertFalse(LibTestExactDecimal.isSumResult(1e66, 10, -10000000015, -1, 1e67, 9), "two above");
    }

    /// #332: int224.max + 1 is 2^223, which packs as int224.max at the same
    /// exponent, so adding a positive number does not lower the value.
    function testAddInt224MaxPlusOne() external pure {
        Float max = LibDecimalFloat.packLossless(type(int224).max, 0);
        Float sum = max.add(LibDecimalFloat.packLossless(1, 0));
        assertEq(Float.unwrap(sum), Float.unwrap(max));
        assertEq(Float.unwrap(max.add(LibDecimalFloat.packLossless(2, 0))), Float.unwrap(max));
        Float min = LibDecimalFloat.packLossless(type(int224).min, -7);
        assertEq(Float.unwrap(min.add(LibDecimalFloat.packLossless(-1, -7))), Float.unwrap(min));
    }
}
