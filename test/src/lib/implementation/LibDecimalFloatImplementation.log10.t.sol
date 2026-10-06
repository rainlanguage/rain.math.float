// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LogTest, console2} from "../../../abstract/LogTest.sol";
import {Log10Zero, Log10Negative} from "src/error/ErrDecimalFloat.sol";

contract LibDecimalFloatImplementationLog10Test is LogTest {
    function checkLog10(
        int256 signedCoefficient,
        int256 exponent,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal {
        address tables = logTables();
        uint256 aGas = gasleft();
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.log10(tables, signedCoefficient, exponent);
        uint256 bGas = gasleft();
        // this is just a log, if the cast causes problems then the dev can
        // deal with it.
        // forge-lint: disable-next-line(unsafe-typecast)
        console2.log("%d %d Gas used: %d", uint256(signedCoefficient), uint256(exponent), aGas - bGas);
        assertEq(actualSignedCoefficient, expectedSignedCoefficient);
        assertEq(actualExponent, expectedExponent);
    }

    function testExactLogs() external {
        checkLog10(1, 0, 0, 0);
        checkLog10(10, 0, 1, 0);
        checkLog10(100, 0, 2, 0);
        checkLog10(1000, 0, 3, 0);
        checkLog10(10000, 0, 4, 0);
        checkLog10(1e37, -37, 0, 0);
        checkLog10(1e76, -76, 0, 0);
    }

    function testExactLookupsLog10() external {
        checkLog10(1001, 0, 3.0004e76, -76);
        checkLog10(100.1e1, -1, 2.0004e76, -76);
        checkLog10(10.01e2, -2, 1.0004e76, -76);
        checkLog10(1.001e3, -3, 0.0004e76, -76);

        checkLog10(10.02e2, -2, 1.0009e76, -76);
        // log10(10.99) = 1.040997692... (bc -l).
        checkLog10(10.99e2, -2, 1.041e76, -76);

        checkLog10(6566, 0, 3.8173e76, -76);

        checkLog10(20, 0, 1.301e76, -76);
        checkLog10(200, 0, 2.301e76, -76);
        checkLog10(90, 0, 1.9542e76, -76);
        checkLog10(900, 0, 2.9542e76, -76);
    }

    function testInterpolatedLookups() external {
        checkLog10(10.015e3, -3, 1.00065e76, -76);
    }

    function testSub1() external {
        checkLog10(0.1001e4, -4, -0.9996e76, -76);

        checkLog10(0.5e1, -1, -0.301e76, -76);
    }

    function log10External(int256 signedCoefficient, int256 exponent) external returns (int256, int256) {
        return LibDecimalFloatImplementation.log10(logTables(), signedCoefficient, exponent);
    }

    function testLog10ZeroReverts() external {
        vm.expectRevert(abi.encodeWithSelector(Log10Zero.selector));
        this.log10External(0, 0);
    }

    function testLog10NegativeReverts(int256 signedCoefficient, int256 exponent) external {
        signedCoefficient = bound(signedCoefficient, type(int256).min, -1);
        vm.expectRevert(abi.encodeWithSelector(Log10Negative.selector, signedCoefficient, exponent));
        this.log10External(signedCoefficient, exponent);
    }

    function testLog10One() external {
        unchecked {
            int256 exponent = 0;
            for (int256 i = 1; exponent >= -76;) {
                checkLog10(i, exponent, 0, 0);
                exponent--;
                i *= 10;
            }
        }
    }

    function checkLog10Eq(int256 signedCoefficient, int256 exponent, int256 expected) internal {
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.log10(logTables(), signedCoefficient, exponent);
        assertTrue(LibDecimalFloatImplementation.eq(actualSignedCoefficient, actualExponent, expected, 0), "log10");
    }

    /// Coefficients too small to take their full shift at the floor.
    /// log10(c * 10^e) = log10(c) + e.
    function testLog10AtFloor() external {
        int256 min = type(int256).min;
        checkLog10(1, min, min, 0);
        checkLog10(10, min, min + 1, 0);
        checkLog10(1e75, min, min + 75, 0);
        checkLog10(1, min + 1, min + 1, 0);
        checkLog10(1, min + 75, min + 75, 0);
        // The result is an integer at this magnitude. log10(2) rounds up.
        checkLog10Eq(2, min, min + 1);
        checkLog10Eq(2, min + 1, min + 2);
        checkLog10Eq(5e75, min, min + 76);
    }

    /// Near the floor, log10(c * 10^e) is log10(c) + e to within the integer
    /// the result rounds to.
    function testLog10NearFloorMatchesShifted(int256 signedCoefficient, uint256 headroom) external {
        signedCoefficient = bound(signedCoefficient, 1, 1e10);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exponent = type(int256).min + int256(bound(headroom, 3, 50));
        address tables = logTables();
        (int256 actualCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.log10(tables, signedCoefficient, exponent);
        (int256 expectedCoefficient, int256 expectedExponent) =
            LibDecimalFloatImplementation.log10(tables, signedCoefficient, 0);
        (expectedCoefficient, expectedExponent) =
            LibDecimalFloatImplementation.add(expectedCoefficient, expectedExponent, exponent, 0);
        (int256 diffCoefficient, int256 diffExponent) =
            LibDecimalFloatImplementation.sub(actualCoefficient, actualExponent, expectedCoefficient, expectedExponent);
        assertTrue(LibDecimalFloatImplementation.lt(diffCoefficient, diffExponent, 2, 0), "below");
        assertTrue(LibDecimalFloatImplementation.gt(diffCoefficient, diffExponent, -2, 0), "above");
    }
}
