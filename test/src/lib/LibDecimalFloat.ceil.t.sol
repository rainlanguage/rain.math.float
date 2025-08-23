// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {Test, console2} from "forge-std/Test.sol";

contract LibDecimalFloatCeilTest is Test {
    using LibDecimalFloat for Float;

    function testCeilNotReverts(Float float) external pure {
        float.ceil();
    }

    function checkCeil(
        int256 signedCoefficient,
        int256 exponent,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal pure {
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloat.ceil(LibDecimalFloat.packLossless(signedCoefficient, exponent)).unpack();

        if (
            !LibDecimalFloatImplementation.eq(
                actualSignedCoefficient, actualExponent, expectedSignedCoefficient, expectedExponent
            )
        ) {
            console2.log("signedCoefficient", signedCoefficient);
            console2.log("exponent", exponent);
            console2.log("expectedSignedCoefficient", expectedSignedCoefficient);
            console2.log("expectedExponent", expectedExponent);
            console2.log("actualSignedCoefficient", actualSignedCoefficient);
            console2.log("actualExponent", actualExponent);
            revert("Ceil check failed");
        }
    }

    /// Every non negative exponent is identity for ceil.
    function testCeilNonNegative(int224 x, int256 exponent) external pure {
        exponent = bound(exponent, 0, type(int32).max);
        checkCeil(x, exponent, x, exponent);
    }

    /// If the exponent is less than -76 then the ceil is 1 if x is positive,
    /// or 0 if x is negative.
    function testCeilLessThanMin(int224 x, int256 exponent) external pure {
        exponent = bound(exponent, type(int32).min, -77);
        if (x <= 0) {
            checkCeil(x, exponent, 0, exponent);
        } else {
            checkCeil(x, exponent, 1, 0);
        }
    }

    /// For exponents [-76,-1] the ceil is the + 1.
    function testCeilInRange(int224 x, int256 exponent) external pure {
        exponent = bound(exponent, -76, -1);
        int256 scale = int256(10 ** uint256(-exponent));

        int256 characteristic = x / scale;
        if (characteristic == 0) {
            if (x > 0) {
                // If the characteristic is 0 and x is positive then the ceil is 1.
                checkCeil(x, exponent, 1, 0);
            } else {
                // If the characteristic is 0 and x is negative then the ceil is 0.
                checkCeil(x, exponent, 0, exponent);
            }
        } else {
            // If the characteristic is non-zero then we can just add 1 to it
            // if the mantissa is non-zero.
            int256 mantissa = x % scale;
            if (mantissa > 0) {
                // If the mantissa is greater than 0, we need to add 1 to
                // the characteristic to get the ceiling.
                characteristic += 1;
            }
            checkCeil(x, exponent, characteristic * scale, exponent);
        }
    }

    /// Examples
    function testCeilExamples() external pure {
        checkCeil(123456789, 0, 123456789, 0);
        checkCeil(123456789, -1, 12345679000000000000000000000000000000000000000000000000000000000000, -60);
        checkCeil(123456789, -2, 12345680000000000000000000000000000000000000000000000000000000000000, -61);
        checkCeil(123456789, -3, 12345700000000000000000000000000000000000000000000000000000000000000, -62);
        checkCeil(123456789, -4, 12346000000000000000000000000000000000000000000000000000000000000000, -63);
        checkCeil(123456789, -5, 12350000000000000000000000000000000000000000000000000000000000000000, -64);
        checkCeil(123456789, -6, 12400000000000000000000000000000000000000000000000000000000000000000, -65);
        checkCeil(123456789, -7, 13000000000000000000000000000000000000000000000000000000000000000000, -66);
        checkCeil(123456789, -8, 2000000000000000000000000000000000000000000000000000000000000000000, -66);
        checkCeil(123456789, -9, 1, 0);
        checkCeil(123456789, -10, 1, 0);
        checkCeil(123456789, -11, 1, 0);
        checkCeil(type(int224).max, 0, type(int224).max, 0);
        checkCeil(type(int224).min, 0, type(int224).min, 0);
        checkCeil(2.5e37, -37, 3e66, -66);
    }

    /// Test some zeros.
    function testCeilZero(int32 exponent) external pure {
        Float wrapZero = Float.wrap(0);
        Float packZeroBasic = LibDecimalFloat.packLossless(0, 0);
        Float packZero = LibDecimalFloat.packLossless(0, exponent);
        assertTrue(wrapZero.ceil().eq(packZero));
        assertTrue(wrapZero.ceil().eq(packZeroBasic));
        assertEq(Float.unwrap(wrapZero.ceil()), Float.unwrap(packZeroBasic));
    }
}
