// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {DOCUMENTED_LOG10_RAW_ERROR} from "../../../lib/LibTestErrorBound.sol";
import {Log10Zero, Log10Negative} from "src/error/ErrDecimalFloat.sol";
import {LibTestExactDecimal} from "../../../lib/LibTestExactDecimal.sol";
import {LibTranscendentalOracle} from "../../../lib/LibTranscendentalOracle.sol";

/// `log10Unrounded` against the oracle, which is within 1e-67, and its proven
/// `DOCUMENTED_LOG10_RAW_ERROR` units of 1e-50, plus under a unit of the exponent of the
/// oracle's sum when the characteristic is summed by `add`.
contract LibDecimalFloatImplementationLog10UnroundedTest is Test {
    function log10UnroundedExternal(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.log10Unrounded(signedCoefficient, exponent);
    }

    function abs(int256 value) internal pure returns (int256) {
        return value < 0 ? -value : value;
    }

    /// |log10Unrounded - oracle| and the oracle's log as a float.
    function errorAgainstOracle(int256 signedCoefficient, int256 exponent)
        internal
        pure
        returns (int256, int256, int256, int256)
    {
        (int256 actualCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.log10Unrounded(signedCoefficient, exponent);
        // forge-lint: disable-next-line(unsafe-typecast)
        (int256 characteristic, uint256 fraction) = LibTranscendentalOracle.log10(uint256(signedCoefficient), exponent);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedFraction = int256(fraction);
        (int256 expectedCoefficient, int256 expectedExponent) =
            LibTestExactDecimal.addParts(characteristic, 0, signedFraction, -70);
        (int256 errorCoefficient, int256 errorExponent) =
            LibTestExactDecimal.subParts(actualCoefficient, actualExponent, characteristic, 0);
        (errorCoefficient, errorExponent) =
            LibTestExactDecimal.subParts(errorCoefficient, errorExponent, signedFraction, -70);
        return (abs(errorCoefficient), errorExponent, expectedCoefficient, expectedExponent);
    }

    function checkAbsolute(int256 signedCoefficient, int256 exponent) internal pure {
        (int256 errorCoefficient, int256 errorExponent,, int256 expectedExponent) =
            errorAgainstOracle(signedCoefficient, exponent);
        // forge-lint: disable-next-line(unsafe-typecast)
        (int256 boundCoefficient, int256 boundExponent) = (int256(DOCUMENTED_LOG10_RAW_ERROR) * 1e17 + 1, int256(-67));
        if (expectedExponent > -50) {
            (boundCoefficient, boundExponent) =
                LibTestExactDecimal.addParts(boundCoefficient, boundExponent, 1, expectedExponent);
        }
        assertTrue(
            LibTestExactDecimal.cmpParts(errorCoefficient, errorExponent, boundCoefficient, boundExponent) <= 0,
            "log10Unrounded error"
        );
    }

    /// Within a factor 1.001 of 1 the log is all correction and the error is
    /// under 3.27e-49 of it.
    function checkRelative(int256 signedCoefficient, int256 exponent) internal pure {
        (int256 errorCoefficient, int256 errorExponent, int256 expectedCoefficient, int256 expectedExponent) =
            errorAgainstOracle(signedCoefficient, exponent);
        (int256 boundCoefficient, int256 boundExponent) =
            LibTestExactDecimal.mulParts(abs(expectedCoefficient), expectedExponent, 327, -51);
        (boundCoefficient, boundExponent) = LibTestExactDecimal.addParts(boundCoefficient, boundExponent, 1, -67);
        assertTrue(
            LibTestExactDecimal.cmpParts(errorCoefficient, errorExponent, boundCoefficient, boundExponent) <= 0,
            "log10Unrounded relative error"
        );
    }

    function checkExact(int256 signedCoefficient, int256 exponent, int256 expected) internal pure {
        (int256 actualCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.log10Unrounded(signedCoefficient, exponent);
        assertEq(actualCoefficient, expected, "coefficient");
        assertEq(actualExponent, 0, "exponent");
    }

    function testLog10UnroundedPowersOfTen() external pure {
        checkExact(1, 0, 0);
        checkExact(1, -1, -1);
        checkExact(10, 5, 6);
        checkExact(1e75, 0, 75);
        checkExact(1e76, -76, 0);
        checkExact(1e76, 1e30, 1e30 + 76);
    }

    /// Within 75 of the floor the shift the exponent cannot take is the
    /// shortfall, and the log is still exact.
    function testLog10UnroundedPowersOfTenAtFloor() external pure {
        int256 min = type(int256).min;
        checkExact(1, min, min);
        checkExact(10, min, min + 1);
        checkExact(1, min + 74, min + 74);
        checkExact(1, min + 75, min + 75);
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

    /// Either side of each 1.001 edge, near 1 where the seed is exact and
    /// with a characteristic where it is not.
    function testLog10UnroundedTableEdges() external pure {
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

    /// 1.000878 has z about 4.39e-4, where the atanh series' z^14 term is
    /// just under 1000 units of 1e-50 and still moves the log by more than its
    /// relative bound.
    function testLog10UnroundedRelativeSeriesTail() external pure {
        checkRelative(1000878e69, -75);
    }

    /// Either side of the 1e25 characteristic where `add` takes over, and
    /// past where the fixed point sum would overflow.
    function testLog10UnroundedLargeCharacteristic() external pure {
        checkAbsolute(2, 1e25 - 1);
        checkAbsolute(2, 1e25);
        checkAbsolute(2, 9e26);
        checkAbsolute(2, -1e25 + 1);
        checkAbsolute(2, -1e25);
        checkAbsolute(2, -9e26);
        checkAbsolute(31415926535, 1e40);
    }

    function testLog10UnroundedOracle(int256 signedCoefficient, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, 1, type(int256).max);
        exponent = bound(exponent, -200, 200);
        checkAbsolute(signedCoefficient, exponent);
    }

    function testLog10UnroundedOracleLargeExponent(int256 signedCoefficient, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, 1, type(int256).max);
        exponent = bound(exponent, -1e40, 1e40);
        checkAbsolute(signedCoefficient, exponent);
    }
}
