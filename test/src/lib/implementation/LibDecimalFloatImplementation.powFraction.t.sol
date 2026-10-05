// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LogTest} from "../../../abstract/LogTest.sol";
import {LibDecimalFloatImplementation, POW_FIXED_ONE} from "src/lib/implementation/LibDecimalFloatImplementation.sol";

contract LibDecimalFloatImplementationPowFractionTest is LogTest {
    function assertNear(uint256 actual, uint256 expected, uint256 ulps) internal pure {
        uint256 diff = actual > expected ? actual - expected : expected - actual;
        assertLe(diff, ulps, "near");
    }

    /// References are 10^x to 50 places from `bc -l` at scale 200.
    function testExp10Fixed() external pure {
        assertEq(LibDecimalFloatImplementation.exp10Fixed(0), POW_FIXED_ONE);
        assertNear(LibDecimalFloatImplementation.exp10Fixed(POW_FIXED_ONE), 10 * POW_FIXED_ONE, 1e5);
        assertNear(
            LibDecimalFloatImplementation.exp10Fixed(5e49), 316227766016837933199889354443271853371955513932521, 1e5
        );
        assertNear(
            LibDecimalFloatImplementation.exp10Fixed(1e47), 100230523807789967191540488932811055405366845354216, 1e5
        );
        assertNear(LibDecimalFloatImplementation.exp10Fixed(1), POW_FIXED_ONE, 1);
    }

    /// References are log10 to 50 places from `bc -l` at scale 200.
    function testLog10MantissaFixed() external {
        address tables = logTables();
        assertEq(LibDecimalFloatImplementation.log10MantissaFixed(tables, 1e75), 0);
        assertApproxEqAbs(
            LibDecimalFloatImplementation.log10MantissaFixed(tables, 2e75),
            30102999566398119521373889472449302676818988146210,
            1e5
        );
        assertApproxEqAbs(
            LibDecimalFloatImplementation.log10MantissaFixed(tables, 9.999e75),
            99995656838019248961544395597619277332624927405429,
            1e5
        );
        assertApproxEqAbs(
            LibDecimalFloatImplementation.log10MantissaFixed(tables, 1.0001e75),
            4342727686266963731352758509826813109796277589,
            1e5
        );
    }

    function testLog10MantissaFixedRoundTrip(uint256 seed) external {
        int256 signedCoefficient = int256(bound(seed, 1e75, 1e76 - 1));
        int256 log = LibDecimalFloatImplementation.log10MantissaFixed(logTables(), signedCoefficient);
        assertGe(log, 0);
        assertLe(log, int256(POW_FIXED_ONE) + 1e5);
        uint256 roundTrip = LibDecimalFloatImplementation.exp10Fixed(uint256(log));
        assertNear(roundTrip, uint256(signedCoefficient / 1e25), 1e5);
    }

    function testPowFractionOne() external {
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.powFraction(logTables(), 1, 0, 5, -1);
        assertEq(signedCoefficient, 1);
        assertEq(exponent, 0);
    }

    /// A below 1 has a negative log, so the characteristic borrows from the
    /// mantissa. 0.25^0.5 = 0.5.
    function testPowFractionNegativeLog() external {
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.powFraction(logTables(), 25, -2, 5, -1);
        assertEq(exponent, -41);
        assertEq(signedCoefficient, 5e40);
    }
}
