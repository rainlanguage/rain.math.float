// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibExactFloat} from "test/lib/LibExactFloat.sol";
import {zeroAt} from "test/lib/LibTestFloatZero.sol";

import {Test, console2} from "forge-std-1.17.0/src/Test.sol";

contract LibDecimalFloatCeilTest is Test {
    using LibDecimalFloat for Float;

    function checkCeil(
        int256 signedCoefficient,
        int256 exponent,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal pure {
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloat.ceil(LibDecimalFloat.packLossless(signedCoefficient, exponent)).unpack();

        if (!LibExactFloat.eq(actualSignedCoefficient, actualExponent, expectedSignedCoefficient, expectedExponent)) {
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
        // exponent [-76, -1]
        // forge-lint: disable-next-line(unsafe-typecast)
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
        checkCeil(-123456789, 0, -123456789, 0);

        checkCeil(123456789, -1, 12345679000000000000000000000000000000000000000000000000000000000000, -60);
        checkCeil(-123456789, -1, -123456780, -1);

        checkCeil(123456789, -2, 12345680000000000000000000000000000000000000000000000000000000000000, -61);
        checkCeil(-123456789, -2, -1234567e61, -61);

        checkCeil(123456789, -3, 12345700000000000000000000000000000000000000000000000000000000000000, -62);
        checkCeil(-123456789, -3, -123456e62, -62);

        checkCeil(123456789, -4, 12346000000000000000000000000000000000000000000000000000000000000000, -63);
        checkCeil(-123456789, -4, -12345e63, -63);

        checkCeil(123456789, -5, 12350000000000000000000000000000000000000000000000000000000000000000, -64);
        checkCeil(-123456789, -5, -1234e64, -64);

        checkCeil(123456789, -6, 12400000000000000000000000000000000000000000000000000000000000000000, -65);
        checkCeil(-123456789, -6, -123e65, -65);

        checkCeil(123456789, -7, 13000000000000000000000000000000000000000000000000000000000000000000, -66);
        checkCeil(-123456789, -7, -12e66, -66);

        checkCeil(123456789, -8, 2000000000000000000000000000000000000000000000000000000000000000000, -66);
        checkCeil(-123456789, -8, -1e67, -67);

        checkCeil(123456789, -9, 1, 0);
        checkCeil(-123456789, -9, 0, 0);

        checkCeil(123456789, -10, 1, 0);
        checkCeil(-123456789, -10, 0, 0);

        checkCeil(123456789, -11, 1, 0);
        checkCeil(-123456789, -11, 0, 0);

        checkCeil(type(int224).max, 0, type(int224).max, 0);
        checkCeil(type(int224).min, 0, type(int224).min, 0);
        checkCeil(2.5e37, -37, 3e66, -66);
    }

    /// Test some zeros.
    function testCeilZero(int32 exponent) external pure {
        Float wrapZero = Float.wrap(0);
        Float packZeroBasic = LibDecimalFloat.packLossless(0, 0);
        Float packZero = LibDecimalFloat.packLossless(0, exponent);
        (int256 c, int256 e) = wrapZero.ceil().unpack();
        (int256 cz, int256 ez) = packZero.unpack();
        assertTrue(LibExactFloat.eq(c, e, cz, ez));
        (cz, ez) = packZeroBasic.unpack();
        assertTrue(LibExactFloat.eq(c, e, cz, ez));
        assertEq(Float.unwrap(wrapZero.ceil()), Float.unwrap(packZeroBasic));
    }

    /// `ceil` of every Float equals its exact value.
    function testCeilExact(int224 c, int32 e) external pure {
        checkCeilExact(c, e);
    }

    /// Exponents near the decimal point, where the integer and fraction both
    /// carry digits.
    function testCeilExactNearUnit(int224 c, int32 e) external pure {
        checkCeilExact(c, int32(bound(e, -80, 5)));
    }

    function checkCeilExact(int224 c, int32 e) internal pure {
        (int256 rc, int256 re) = LibDecimalFloat.packLossless(c, e).ceil().unpack();
        (int256 xc, int256 xe) = LibExactFloat.ceilParts(c, e);
        assertEq(LibExactFloat.cmpParts(rc, re, xc, xe), 0, "exact ceil");
    }

    /// A zero input of any exponent gives `FLOAT_ZERO`, byte for byte (#687).
    function testFloatCeilZeroBytesExamples() external pure {
        int32[5] memory exponents = [int32(5), type(int32).max, -2, -77, type(int32).min];
        for (uint256 i = 0; i < exponents.length; i++) {
            assertEq(
                Float.unwrap(LibDecimalFloat.ceil(zeroAt(exponents[i]))),
                Float.unwrap(LibDecimalFloat.FLOAT_ZERO),
                "ceil of zero is not FLOAT_ZERO"
            );
        }
    }

    /// A zero input of any exponent gives `FLOAT_ZERO`, byte for byte (#687).
    function testFloatCeilZeroBytes(int32 e) external pure {
        assertEq(
            Float.unwrap(LibDecimalFloat.ceil(zeroAt(e))),
            Float.unwrap(LibDecimalFloat.FLOAT_ZERO),
            "ceil of zero is not FLOAT_ZERO"
        );
    }
}
