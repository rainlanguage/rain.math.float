// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatDecimalAddTest is Test {
    using LibDecimalFloat for Float;

    function addExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (Float)
    {
        (int256 signedCoefficientC, int256 exponentC) =
            LibDecimalFloatImplementation.add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (Float c, bool lossless) = LibDecimalFloat.packLossy(signedCoefficientC, exponentC);
        (lossless);
        return c;
    }

    function addExternal(Float a, Float b) external pure returns (Float) {
        return LibDecimalFloat.add(a, b);
    }

    function testAddPacked(Float a, Float b) external {
        (int256 signedCoefficientA, int256 exponentA) = LibDecimalFloat.unpack(a);
        (int256 signedCoefficientB, int256 exponentB) = LibDecimalFloat.unpack(b);
        try this.addExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB) returns (Float resultParts) {
            (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.unpack(resultParts);
            Float result = this.addExternal(a, b);
            (int256 signedCoefficientUnpacked, int256 exponentUnpacked) = LibDecimalFloat.unpack(result);
            assertEq(signedCoefficient, signedCoefficientUnpacked);
            assertEq(exponent, exponentUnpacked);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.addExternal(a, b);
        }
    }
}
