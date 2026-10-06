// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LogTest} from "../../../abstract/LogTest.sol";
import {LibDecimalFloatImplementation, LOG10_RAW_ERROR} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Log10Zero, Log10Negative} from "src/error/ErrDecimalFloat.sol";
import {LibTranscendentalOracle} from "../../../lib/LibTranscendentalOracle.sol";

/// `log10Unrounded` against the oracle, which is within 1e-67, and its proven
/// `LOG10_RAW_ERROR` units of 1e-50, plus under a unit of the result's
/// exponent when the characteristic is summed by `add`.
contract LibDecimalFloatImplementationLog10UnroundedTest is LogTest {
    function log10UnroundedExternal(int256 signedCoefficient, int256 exponent) external returns (int256, int256) {
        return LibDecimalFloatImplementation.log10Unrounded(logTables(), signedCoefficient, exponent);
    }

    function abs(int256 value) internal pure returns (int256) {
        return value < 0 ? -value : value;
    }

    /// |log10Unrounded - oracle| and the oracle's log as a float.
    function errorAgainstOracle(int256 signedCoefficient, int256 exponent)
        internal
        returns (int256, int256, int256, int256, int256)
    {
        (int256 actualCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.log10Unrounded(logTables(), signedCoefficient, exponent);
        // forge-lint: disable-next-line(unsafe-typecast)
        (int256 characteristic, uint256 fraction) = LibTranscendentalOracle.log10(uint256(signedCoefficient), exponent);
        // forge-lint: disable-next-line(unsafe-typecast)
        (int256 expectedCoefficient, int256 expectedExponent) =
            LibDecimalFloatImplementation.add(characteristic, 0, int256(fraction), -70);
        (int256 errorCoefficient, int256 errorExponent) =
            LibDecimalFloatImplementation.sub(actualCoefficient, actualExponent, characteristic, 0);
        // forge-lint: disable-next-line(unsafe-typecast)
        (errorCoefficient, errorExponent) =
            LibDecimalFloatImplementation.sub(errorCoefficient, errorExponent, int256(fraction), -70);
        return (abs(errorCoefficient), errorExponent, expectedCoefficient, expectedExponent, actualExponent);
    }

    function checkAbsolute(int256 signedCoefficient, int256 exponent) internal {
        (int256 errorCoefficient, int256 errorExponent,,, int256 actualExponent) =
            errorAgainstOracle(signedCoefficient, exponent);
        // forge-lint: disable-next-line(unsafe-typecast)
        (int256 boundCoefficient, int256 boundExponent) = (int256(LOG10_RAW_ERROR) * 1e17 + 1, int256(-67));
        if (actualExponent > -50) {
            (boundCoefficient, boundExponent) =
                LibDecimalFloatImplementation.add(boundCoefficient, boundExponent, 1, actualExponent);
        }
        assertTrue(
            LibDecimalFloatImplementation.lte(errorCoefficient, errorExponent, boundCoefficient, boundExponent),
            "log10Unrounded error"
        );
    }

    /// Within a table step of 1 the log is all correction and the error is
    /// under 3.27e-49 of it.
    function checkRelative(int256 signedCoefficient, int256 exponent) internal {
        (int256 errorCoefficient, int256 errorExponent, int256 expectedCoefficient, int256 expectedExponent,) =
            errorAgainstOracle(signedCoefficient, exponent);
        (int256 boundCoefficient, int256 boundExponent) =
            LibDecimalFloatImplementation.mul(abs(expectedCoefficient), expectedExponent, 327, -51);
        (boundCoefficient, boundExponent) = LibDecimalFloatImplementation.add(boundCoefficient, boundExponent, 1, -67);
        assertTrue(
            LibDecimalFloatImplementation.lte(errorCoefficient, errorExponent, boundCoefficient, boundExponent),
            "log10Unrounded relative error"
        );
    }

    function checkExact(int256 signedCoefficient, int256 exponent, int256 expected) internal {
        (int256 actualCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.log10Unrounded(logTables(), signedCoefficient, exponent);
        assertEq(actualCoefficient, expected, "coefficient");
        assertEq(actualExponent, 0, "exponent");
    }

    function testLog10UnroundedPowersOfTen() external {
        checkExact(1, 0, 0);
        checkExact(1, -1, -1);
        checkExact(10, 5, 6);
        checkExact(1e75, 0, 75);
        checkExact(1e76, -76, 0);
        checkExact(1e76, 1e30, 1e30 + 76);
    }

    function testLog10UnroundedZero() external {
        vm.expectRevert(abi.encodeWithSelector(Log10Zero.selector));
        this.log10UnroundedExternal(0, 5);
    }

    /// The revert carries the input, not its maximized form.
    function testLog10UnroundedNegative() external {
        vm.expectRevert(abi.encodeWithSelector(Log10Negative.selector, int256(-3), int256(7)));
        this.log10UnroundedExternal(-3, 7);
        vm.expectRevert(abi.encodeWithSelector(Log10Negative.selector, int256(-1e70), int256(-2)));
        this.log10UnroundedExternal(-1e70, -2);
    }

    /// Either side of each table edge, near 1 where the seed is exact and
    /// with a characteristic where it is not.
    function testLog10UnroundedTableEdges() external {
        int256[4] memory edges = [int256(1.001e75 - 1), 1.001e75, 9.999e75 - 1, 9.999e75];
        for (uint256 i = 0; i < edges.length; i++) {
            checkAbsolute(edges[i], -75);
            checkAbsolute(edges[i], -76);
            checkAbsolute(edges[i], -70);
            checkAbsolute(edges[i], 3);
        }
        checkRelative(1.001e75 - 1, -75);
        checkRelative(9.999e75, -76);
    }

    /// Either side of the 1e25 characteristic where `add` takes over, and
    /// past where the fixed point sum would overflow.
    function testLog10UnroundedLargeCharacteristic() external {
        checkAbsolute(2, 1e25 - 1);
        checkAbsolute(2, 1e25);
        checkAbsolute(2, 9e26);
        checkAbsolute(2, -1e25 + 1);
        checkAbsolute(2, -1e25);
        checkAbsolute(2, -9e26);
        checkAbsolute(31415926535, 1e40);
    }

    function testLog10UnroundedOracle(int256 signedCoefficient, int256 exponent) external {
        signedCoefficient = bound(signedCoefficient, 1, type(int256).max);
        exponent = bound(exponent, -200, 200);
        checkAbsolute(signedCoefficient, exponent);
    }

    function testLog10UnroundedOracleLargeExponent(int256 signedCoefficient, int256 exponent) external {
        signedCoefficient = bound(signedCoefficient, 1, type(int256).max);
        exponent = bound(exponent, -1e40, 1e40);
        checkAbsolute(signedCoefficient, exponent);
    }
}
