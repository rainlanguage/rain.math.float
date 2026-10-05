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

    /// References are 10^x to 38 digits from `bc -l` at scale 200.
    function testExp10Fixed() external pure {
        assertEq(LibDecimalFloatImplementation.exp10Fixed(0), POW_FIXED_ONE);
        assertNear(LibDecimalFloatImplementation.exp10Fixed(POW_FIXED_ONE), 10 * POW_FIXED_ONE, 1000);
        assertNear(LibDecimalFloatImplementation.exp10Fixed(5e36), 31622776601683793319988935444327185337, 1000);
        assertNear(LibDecimalFloatImplementation.exp10Fixed(1e33), 10002302850208247526835942556719413318, 1000);
        assertNear(LibDecimalFloatImplementation.exp10Fixed(1), POW_FIXED_ONE, 1);
    }

    /// References are log10 to 37 places from `bc -l` at scale 200.
    function testLog10MantissaFixed() external {
        address tables = logTables();
        assertEq(LibDecimalFloatImplementation.log10MantissaFixed(tables, 1e75), 0);
        assertApproxEqAbs(
            LibDecimalFloatImplementation.log10MantissaFixed(tables, 2e75), 3010299956639811952137388947244930267, 100
        );
        assertApproxEqAbs(
            LibDecimalFloatImplementation.log10MantissaFixed(tables, 9.999e75),
            9999565683801924896154439559761927733,
            100
        );
        assertApproxEqAbs(
            LibDecimalFloatImplementation.log10MantissaFixed(tables, 1.0001e75), 434272768626696373135275850982681, 100
        );
    }

    function testLog10MantissaFixedRoundTrip(uint256 seed) external {
        int256 signedCoefficient = int256(bound(seed, 1e75, 1e76 - 1));
        int256 log = LibDecimalFloatImplementation.log10MantissaFixed(logTables(), signedCoefficient);
        assertGe(log, 0);
        assertLe(log, int256(POW_FIXED_ONE) + 1000);
        uint256 roundTrip = LibDecimalFloatImplementation.exp10Fixed(uint256(log));
        assertNear(roundTrip, uint256(signedCoefficient / 1e38), 1000);
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
        assertEq(exponent, -38);
        assertApproxEqAbs(signedCoefficient, 5e37, 1000);
    }
}
