// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LogTest} from "../../abstract/LogTest.sol";

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {ZeroNegativePower, Log10Negative} from "src/error/ErrDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {console2} from "forge-std/Test.sol";

contract LibDecimalFloatPowTest is LogTest {
    using LibDecimalFloat for Float;

    function diffLimit() internal pure returns (Float) {
        return LibDecimalFloat.packLossless(94, -3);
    }

    function checkPow(
        int256 signedCoefficientA,
        int256 exponentA,
        int256 signedCoefficientB,
        int256 exponentB,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal {
        Float a = LibDecimalFloat.packLossless(signedCoefficientA, exponentA);
        Float b = LibDecimalFloat.packLossless(signedCoefficientB, exponentB);
        address tables = logTables();
        uint256 beforeGas = gasleft();
        Float c = a.pow(b, tables);
        uint256 afterGas = gasleft();
        console2.log("Gas used:", beforeGas - afterGas);
        (int256 actualSignedCoefficient, int256 actualExponent) = c.unpack();
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signedCoefficient");
        assertEq(actualExponent, expectedExponent, "exponent");
    }

    function testPows() external {
        // 0.5 ^ 30 = 9.3132257e-10
        checkPow(
            5e37, -38, 3e37, -36, 9.328358208955223880597014925373134328358208955223880597014925373134e66, -66 - 10
        );
        // 0.5 ^ 60 = 8.6736174e-19
        checkPow(
            5e37, -38, 6e37, -36, 8.710801393728222996515679442508710801393728222996515679442508710801e66, -66 - 19
        );
        // Issues found in fuzzing from here.
        // 99999 ^ 12182 = 8.853071703048649170130397094169464632911643045383977634639832230468640539353...e60910
        // 8.853071703048649170130397094169464632911643045383977634639832230468640539353e75 e60910
        checkPow(99999, 0, 12182, 0, 1000, 60907);
        checkPow(1785215562, 0, 18, 0, 3388, 163);
    }

    /// a^b is error for negative a and all b.
    /// In the future we may support negative bases with integer exponents.
    /// https://github.com/rainlanguage/rain.math.float/issues/88
    function testNegativePowError(Float a, Float b) external {
        // We can't simply minus 0 to get a negative base.
        vm.assume(!a.isZero());
        // Anything to 0 power is 1, including negative base.
        vm.assume(!b.isZero());
        if (a.gt(LibDecimalFloat.FLOAT_ZERO)) {
            a = a.minus();
        }
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        vm.expectRevert(abi.encodeWithSelector(Log10Negative.selector, signedCoefficientA, exponentA));
        this.powExternal(a, b);
    }

    /// a^0 = 1 for all a including 0^0.
    function testPowBZero(Float a, int32 exponentB) external {
        Float b = LibDecimalFloat.packLossless(0, exponentB);
        // If b is zero then the result is always 1.
        address tables = logTables();
        Float c = a.pow(b, tables);
        assertTrue(c.eq(LibDecimalFloat.packLossless(1, 0)), "c is not 1");
    }

    /// 0^b is defined as 0 for all b > 0.
    function testPowAZero(int32 exponentA, Float b) external {
        // 0^0 is defined as 1.
        vm.assume(b.gt(LibDecimalFloat.FLOAT_ZERO));
        // If a is zero then the result is always zero.
        Float a = LibDecimalFloat.packLossless(0, exponentA);
        address tables = logTables();
        Float c = a.pow(b, tables);
        assertTrue(c.isZero(), "c is not zero");
    }

    /// 0^a is error for all a < 0.
    function testPowAZeroNegative(Float b) external {
        vm.assume(b.lt(LibDecimalFloat.FLOAT_ZERO));
        vm.expectRevert(abi.encodeWithSelector(ZeroNegativePower.selector, b));
        this.powExternal(LibDecimalFloat.FLOAT_ZERO, b);
    }

    function checkRoundTrip(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
    {
        Float a = LibDecimalFloat.packLossless(signedCoefficientA, exponentA);
        Float b = LibDecimalFloat.packLossless(signedCoefficientB, exponentB);
        address tables = logTables();
        Float c = a.pow(b, tables);

        Float roundTrip = c.pow(b.inv(), tables);

        Float diff = a.div(roundTrip).sub(LibDecimalFloat.FLOAT_ONE).abs();

        assertTrue(!diff.gt(diffLimit()), "diff");
    }

    /// X^Y^(1/Y) = X
    /// Can generally round trip whatever within 0.25% of the original value.
    function testRoundTripSimple() external {
        checkRoundTrip(5, 0, 2, 0);
        checkRoundTrip(5, 0, 3, 0);
        checkRoundTrip(50, 0, 40, 0);
        checkRoundTrip(5, -1, 3, -1);
        checkRoundTrip(5, -1, 2, -1);
        checkRoundTrip(5, 10, 3, 5);
        checkRoundTrip(5, -1, 100, 0);
        checkRoundTrip(7721, 0, -1, -2);
        checkRoundTrip(4157, 0, -1, -2);
    }

    function powExternal(Float a, Float b) external returns (Float) {
        return a.pow(b, logTables());
    }

    function testRoundTripFuzzPow(Float a, Float b) external {
        try this.powExternal(a, b) returns (Float c) {
            // If b is zero we'll divide by zero on the inv.
            // If c is 1 then it's not round trippable because 1^x = 1 for all x.
            // C will be 1 when a is 1 or b is 0 (or very close to either).
            if (b.isZero() || c.eq(LibDecimalFloat.packLossless(1, 0))) {} else {
                Float inv = b.inv();
                try this.powExternal(c, inv) returns (Float roundTrip) {
                    if (roundTrip.isZero()) {} else {
                        Float diff = a.div(roundTrip).sub(LibDecimalFloat.packLossless(1, 0)).abs();
                        assertTrue(!diff.gt(diffLimit()), "diff");
                    }
                } catch (bytes memory err) {}
            }
        } catch (bytes memory err) {}
    }
}
