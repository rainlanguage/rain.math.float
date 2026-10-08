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

    /// Reverts only where the exact sum is beyond the largest Float of its
    /// sign, and otherwise agrees with the unpacked path.
    function testAddPacked(Float a, Float b) external {
        (int256 signedCoefficientA, int256 exponentA) = LibDecimalFloat.unpack(a);
        (int256 signedCoefficientB, int256 exponentB) = LibDecimalFloat.unpack(b);
        if (LibTestExactDecimal.addOverflows(signedCoefficientA, exponentA, signedCoefficientB, exponentB)) {
            (int256 signedCoefficientSum, int256 exponentSum) =
                LibTestExactDecimal.addParts(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
            vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficientSum, exponentSum));
            this.addExternal(a, b);
            return;
        }
        Float resultParts = this.addExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.unpack(resultParts);
        Float result = this.addExternal(a, b);
        (int256 signedCoefficientUnpacked, int256 exponentUnpacked) = LibDecimalFloat.unpack(result);
        assertEq(signedCoefficient, signedCoefficientUnpacked);
        assertEq(exponent, exponentUnpacked);
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
