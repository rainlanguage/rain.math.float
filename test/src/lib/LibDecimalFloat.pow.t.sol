// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LogTest} from "../../abstract/LogTest.sol";

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

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
        console2.logInt(signedCoefficientA);
        console2.logInt(exponentA);
        (int256 actualSignedCoefficient, int256 actualExponent) = c.unpack();
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signedCoefficient");
        assertEq(actualExponent, expectedExponent, "exponent");
    }

    function testPows() external {
        checkPow(5e37, -38, 3e37, -36, 9.3283582089552238805970149253731343283e37, -47);
        checkPow(5e37, -38, 6e37, -36, 8.7108013937282229965156794425087108013e37, -56);
        // // Issues found in fuzzing from here.
        checkPow(99999, 0, 12182, 0, 1000, 60907);
        checkPow(1785215562, 0, 18, 0, 3388, 163);
    }

    /// a^0 = 1 for all a including 0^0.
    function testPowBZero(Float a, int32 exponentB) external {
        Float b = LibDecimalFloat.packLossless(0, exponentB);
        // If b is zero then the result is always 1.
        address tables = logTables();
        Float c = a.pow(b, tables);
        assertTrue(c.eq(LibDecimalFloat.packLossless(1, 0)), "c is not 1");
    }

    /// 0^b is defined as 0 for all b != 0.
    function testPowAZero(int32 exponentA, Float b) external {
        // 0^0 is defined as 1.
        vm.assume(!b.isZero());
        // If a is zero then the result is always zero.
        Float a = LibDecimalFloat.packLossless(0, exponentA);
        address tables = logTables();
        Float c = a.pow(b, tables);
        assertTrue(c.isZero(), "c is not zero");
    }

    function checkRoundTrip(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
    {
        Float a = LibDecimalFloat.packLossless(signedCoefficientA, exponentA);
        Float b = LibDecimalFloat.packLossless(signedCoefficientB, exponentB);
        address tables = logTables();
        Float c = a.pow(b, tables);

        Float roundTrip = c.pow(b.inv(), tables);

        Float diff = a.div(roundTrip).sub(LibDecimalFloat.packLossless(1, 0)).abs();

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

    function testRoundTripFuzz(Float a, Float b) external {
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
