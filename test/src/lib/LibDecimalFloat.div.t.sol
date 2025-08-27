// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {Test} from "forge-std/Test.sol";

contract LibDecimalFloatDivTest is Test {
    using LibDecimalFloat for Float;

    function divExternal(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        external
        pure
        returns (Float)
    {
        (int256 signedCoefficientC, int256 exponentC) =
            LibDecimalFloatImplementation.div(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        (Float c, bool lossless) = LibDecimalFloat.packLossy(signedCoefficientC, exponentC);
        (lossless);
        return c;
    }

    function divExternal(Float floatA, Float floatB) external pure returns (Float) {
        return LibDecimalFloat.div(floatA, floatB);
    }

    function testDivPacked(Float a, Float b) external {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        try this.divExternal(signedCoefficientA, exponentA, signedCoefficientB, exponentB) returns (Float resultParts) {
            (int256 signedCoefficient, int256 exponent) = LibDecimalFloat.unpack(resultParts);
            Float float = this.divExternal(a, b);
            (int256 signedCoefficientFloat, int256 exponentFloat) = float.unpack();
            assertEq(signedCoefficient, signedCoefficientFloat);
            assertEq(exponent, exponentFloat);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            this.divExternal(a, b);
        }
    }

    function testDivByOneFloat(int224 signedCoefficient, int32 exponent) external pure {
        exponent = int32(bound(exponent, int256(type(int32).min) + 65, int256(type(int32).max)));
        Float float = LibDecimalFloat.packLossless(signedCoefficient, exponent);
        int256 one = 1;
        for (int256 oneExponent = 0; oneExponent >= -65; --oneExponent) {
            Float result = LibDecimalFloat.div(float, LibDecimalFloat.packLossless(one, oneExponent));
            assertTrue(result.eq(float));
            if (oneExponent == -65) {
                break;
            }
            one *= 10;
        }
    }

    function testDivByNegativeOneFloat(int224 signedCoefficient, int32 exponent) external pure {
        exponent = int32(bound(exponent, int256(type(int32).min) + 65, int256(type(int32).max) - 65));
        Float float = LibDecimalFloat.packLossless(signedCoefficient, exponent);
        int256 negativeOne = -1;
        for (int256 oneExponent = 0; oneExponent >= -65; --oneExponent) {
            Float result = LibDecimalFloat.div(float, LibDecimalFloat.packLossless(negativeOne, oneExponent));
            assertTrue(result.eq(float.minus()));
            if (oneExponent == -65) {
                break;
            }
            negativeOne *= 10;
        }
    }
}
