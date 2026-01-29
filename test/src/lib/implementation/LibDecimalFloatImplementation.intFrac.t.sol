// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";

import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

contract LibDecimalFloatImplementationIntFracTest is Test {
    function checkIntFrac(int256 signedCoefficient, int256 exponent, int256 expectedInteger, int256 expectedFraction)
        internal
        pure
    {
        (int256 actualInteger, int256 actualFraction) =
            LibDecimalFloatImplementation.intFrac(signedCoefficient, exponent);

        assertEq(actualInteger, expectedInteger, "Integer mismatch");
        assertEq(actualFraction, expectedFraction, "Fraction mismatch");
    }

    function testIntFracExamples() public pure {
        checkIntFrac(0, 0, 0, 0);
        checkIntFrac(0, 1, 0, 0);

        checkIntFrac(5.4304950862250382e16, -16, 5e16, 4304950862250382);
        checkIntFrac(-5.4304950862250382e16, -16, -5e16, -0.4304950862250382e16);

        checkIntFrac(5.4304950862250382e16, -76, 0, 5.4304950862250382e16);
        checkIntFrac(-5.4304950862250382e16, -76, 0, -5.4304950862250382e16);

        // Exact multiple => zero fraction
        checkIntFrac(5e16, -16, 5e16, 0);
        checkIntFrac(-5e16, -16, -5e16, 0);
        // Off-by-one around the multiple
        checkIntFrac(5e16 + 1, -16, 5e16, 1);
        checkIntFrac(-5e16 - 1, -16, -5e16, -1);

        // Boundary at exponent -76 (scale = 1e76)
        checkIntFrac(1e76, -76, 1e76, 0);
        checkIntFrac(1e76 + 1, -76, 1e76, 1);
        checkIntFrac(-1e76, -76, -1e76, 0);
        checkIntFrac(-1e76 - 1, -76, -1e76, -1);

        // Beyond boundary at exponent -77 (scale > int256.max): integer must be 0
        checkIntFrac(1, -77, 0, 1);
        checkIntFrac(-1, -77, 0, -1);
    }

    function testIntFracNonNegExponent(int256 signedCoefficient, int256 exponent) public pure {
        exponent = bound(exponent, 0, type(int256).max);
        checkIntFrac(signedCoefficient, exponent, signedCoefficient, 0);
    }

    function testIntFracNegExponentLarge(int256 signedCoefficient, int256 exponent) public pure {
        exponent = bound(exponent, type(int256).min, -77);
        checkIntFrac(signedCoefficient, exponent, 0, signedCoefficient);
    }

    function testIntFracNegExponentSmall(int256 signedCoefficient) public pure {
        for (int256 exponent = 1; exponent <= 76; exponent++) {
            // exponent [1, 76]
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 scale = int256(10 ** uint256(exponent));

            int256 expectedFraction = signedCoefficient % scale;
            int256 expectedInteger = signedCoefficient / scale * scale;

            checkIntFrac(signedCoefficient, -exponent, expectedInteger, expectedFraction);
        }
    }
}
