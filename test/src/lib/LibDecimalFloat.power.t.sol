// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

import {LogTest} from "../../abstract/LogTest.sol";

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

import {console2} from "forge-std/Test.sol";

contract LibDecimalFloatPowerTest is LogTest {
    using LibDecimalFloat for Float;

    function checkPower(
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
        Float c = a.power(b, tables);
        uint256 afterGas = gasleft();
        console2.log("%d %d Gas used: %d", uint256(signedCoefficientA), uint256(exponentA), beforeGas - afterGas);
        (int256 actualSignedCoefficient, int256 actualExponent) = c.unpack();
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signedCoefficient");
        assertEq(actualExponent, expectedExponent, "exponent");
    }

    function testPowers() external {
        checkPower(5e37, -38, 3e37, -36, 9.3283582089552238805970149253731343283e37, -47);
        checkPower(5e37, -38, 6e37, -36, 8.7108013937282229965156794425087108013e37, -56);
        // // Issues found in fuzzing from here.
        checkPower(99999, 0, 12182, 0, 1000, 60907);
        checkPower(1785215562, 0, 18, 0, 3388, 163);
    }

    function checkRoundTrip(int256 signedCoefficientA, int256 exponentA, int256 signedCoefficientB, int256 exponentB)
        internal
    {
        Float a = LibDecimalFloat.packLossless(signedCoefficientA, exponentA);
        Float b = LibDecimalFloat.packLossless(signedCoefficientB, exponentB);
        address tables = logTables();
        Float c = a.power(b, tables);
        (int256 signedCoefficientC, int256 exponentC) = c.unpack();
        console2.log("c");
        console2.logInt(signedCoefficientC);
        console2.logInt(exponentC);
        Float roundTrip = c.power(b.inv(), tables);

        (int256 signedCoefficientRoundTrip, int256 exponentRoundTrip) = roundTrip.unpack();
        console2.log("round trip");
        console2.logInt(signedCoefficientRoundTrip);
        console2.logInt(exponentRoundTrip);

        Float diff = a.divide(roundTrip).sub(LibDecimalFloat.packLossless(1, 0)).abs();

        assertTrue(!diff.gt(LibDecimalFloat.packLossless(0.002e3, -3)), "diff");
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
    }

    function powerExternal(Float a, Float b) external returns (Float) {
        return a.power(b, logTables());
    }

    function testRoundTripFuzz(Float a, Float b) external {
        try this.powerExternal(a, b) returns (Float c) {
            // If b is zero we'll divide by zero on the inv.
            // If c is 1 then it's not round trippable because 1^x = 1 for all x.
            // C will be 1 when a is 1 or b is 0 (or very close to either).
            if (b.isZero() || c.eq(LibDecimalFloat.packLossless(1, 0))) {} else {
                Float inv = b.inv();
                try this.powerExternal(c, inv) returns (Float roundTrip) {
                    if (roundTrip.isZero()) {} else {
                        Float diff = a.divide(roundTrip).sub(LibDecimalFloat.packLossless(1, 0)).abs();
                        console2.log("a");
                        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
                        console2.logInt(signedCoefficientA);
                        console2.logInt(exponentA);
                        console2.log("b");
                        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
                        console2.logInt(signedCoefficientB);
                        console2.logInt(exponentB);
                        console2.log("c");
                        (int256 signedCoefficientC, int256 exponentC) = c.unpack();
                        console2.logInt(signedCoefficientC);
                        console2.logInt(exponentC);
                        console2.log("inv");
                        (int256 signedCoefficientInv, int256 exponentInv) = inv.unpack();
                        console2.logInt(signedCoefficientInv);
                        console2.logInt(exponentInv);
                        console2.log("roundTrip");
                        (int256 signedCoefficientRoundTrip, int256 exponentRoundTrip) = roundTrip.unpack();
                        console2.logInt(signedCoefficientRoundTrip);
                        console2.logInt(exponentRoundTrip);
                        console2.log("diff");
                        (int256 signedCoefficientDiff, int256 exponentDiff) = diff.unpack();
                        console2.logInt(signedCoefficientDiff);
                        console2.logInt(exponentDiff);

                        assertTrue(!diff.gt(LibDecimalFloat.packLossless(285, -4)), "diff");
                    }
                } catch (bytes memory err) {}
            }
        } catch (bytes memory err) {}
    }
}
