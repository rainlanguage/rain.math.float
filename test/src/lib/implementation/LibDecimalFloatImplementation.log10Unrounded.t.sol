// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation, LOG10_RAW_ERROR} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Log10Zero, Log10Negative, ExponentOverflow} from "src/error/ErrDecimalFloat.sol";
import {LibTranscendentalOracle} from "../../../lib/LibTranscendentalOracle.sol";
import {LibTestExactDecimal} from "test/lib/LibTestExactDecimal.sol";

/// `log10Unrounded` against the oracle, which is within 1e-67, and its proven
/// `LOG10_RAW_ERROR` units of 1e-50, plus under a unit of the exponent of the
/// oracle's sum when the characteristic is summed by `add`.
contract LibDecimalFloatImplementationLog10UnroundedTest is Test {
    function log10UnroundedExternal(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.log10Unrounded(signedCoefficient, exponent);
    }

    function abs(int256 value) internal pure returns (int256) {
        return value < 0 ? -value : value;
    }

    /// Whether |log10Unrounded - oracle| is within the bound terms, exactly.
    function withinOracle(
        int256 signedCoefficient,
        int256 exponent,
        int256[] memory boundCoefficients,
        int256[] memory boundExponents
    ) internal pure returns (bool) {
        (int256 actualCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.log10Unrounded(signedCoefficient, exponent);
        // forge-lint: disable-next-line(unsafe-typecast)
        (int256 characteristic, uint256 fraction) = LibTranscendentalOracle.log10(uint256(signedCoefficient), exponent);
        int256[] memory coefficients = new int256[](3);
        int256[] memory exponents = new int256[](3);
        (coefficients[0], exponents[0]) = (actualCoefficient, actualExponent);
        (coefficients[1], exponents[1]) = (-characteristic, 0);
        // forge-lint: disable-next-line(unsafe-typecast)
        (coefficients[2], exponents[2]) = (-int256(fraction), -70);
        return LibTestExactDecimal.absSumLte(coefficients, exponents, boundCoefficients, boundExponents);
    }

    function checkAbsolute(int256 signedCoefficient, int256 exponent) internal pure {
        // forge-lint: disable-next-line(unsafe-typecast)
        (int256 characteristic,) = LibTranscendentalOracle.log10(uint256(signedCoefficient), exponent);
        int256[] memory boundCoefficients = new int256[](3);
        int256[] memory boundExponents = new int256[](3);
        // forge-lint: disable-next-line(unsafe-typecast)
        (boundCoefficients[0], boundExponents[0]) = (int256(LOG10_RAW_ERROR), -50);
        (boundCoefficients[1], boundExponents[1]) = (1, -67);
        // `add` rounds the sum to the characteristic's int256 unit.
        if (characteristic != 0) {
            int256 unit = LibTestExactDecimal.int256Unit(characteristic, 0);
            if (unit > -50) {
                (boundCoefficients[2], boundExponents[2]) = (1, unit);
            }
        }
        assertTrue(withinOracle(signedCoefficient, exponent, boundCoefficients, boundExponents), "log10Unrounded error");
    }

    /// Within a factor 1.001 of 1 the log is all correction and the error is
    /// under 3.27e-49 of it.
    function checkRelative(int256 signedCoefficient, int256 exponent) internal pure {
        // forge-lint: disable-next-line(unsafe-typecast)
        (int256 characteristic, uint256 fraction) = LibTranscendentalOracle.log10(uint256(signedCoefficient), exponent);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expected = characteristic * 1e70 + int256(fraction);
        int256[] memory boundCoefficients = new int256[](2);
        int256[] memory boundExponents = new int256[](2);
        (boundCoefficients[0], boundExponents[0]) = (abs(expected) * 327, -121);
        (boundCoefficients[1], boundExponents[1]) = (1, -67);
        assertTrue(
            withinOracle(signedCoefficient, exponent, boundCoefficients, boundExponents),
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

    /// #422: (2e75, int256.max) panicked. The characteristic reaches
    /// int256.max exactly at 10^int256.max, by each of the coefficient's
    /// paths: scaled up, in place, past 1e76, and rounded up to the next
    /// power of ten from 9.999e75. The reduced path keeps the characteristic
    /// at int256.max with a log just under int256.max + 1.
    function testLog10UnroundedCharacteristicCeiling() external pure {
        int256 max = type(int256).max;
        checkExact(1, max, max);
        checkExact(1e75, max - 75, max);
        checkExact(1e76, max - 76, max);
        checkAbsolute(9.999e75, max - 76);
        checkAbsolute(1e76 - 1, max - 76);
        checkAbsolute(9.999e75 - 1, max - 75);
    }

    /// A characteristic one past int256.max, on each path above, reverts
    /// `ExponentOverflow` with the input.
    function testLog10UnroundedCharacteristicOverflow() external {
        int256 max = type(int256).max;
        int256[2][7] memory inputs = [
            [int256(10), max],
            [int256(2e75), max],
            [int256(1e75), max - 74],
            [int256(1e76), max - 75],
            [int256(9.999e75), max - 75],
            [int256(1e76 - 1), max - 75],
            [type(int256).max, max]
        ];
        for (uint256 i = 0; i < inputs.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, inputs[i][0], inputs[i][1]));
            this.log10UnroundedExternal(inputs[i][0], inputs[i][1]);
        }
    }

    /// The characteristic is the floor of the log, rounded up from 9.999 of
    /// a power of ten, so it passes int256.max exactly when the coefficient's
    /// digits d, plus one from 9.999 10^d, plus the exponent do.
    function testLog10UnroundedCharacteristicOverflowFuzz(int256 signedCoefficient, int256 room) external {
        signedCoefficient = bound(signedCoefficient, 1, type(int256).max);
        room = bound(room, 0, 160);
        int256 exponent = type(int256).max - room;
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 digits = LibTestExactDecimal.digits(LibTestExactDecimal.u512(uint256(signedCoefficient))) - 1;
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 power = int256(10 ** uint256(digits));
        // Below 1000, c is at most 10^(d + 1) - 1, under 9.999 10^d.
        bool roundsUp = power >= 1000 && signedCoefficient / (power / 1000) >= 9999;
        int256 characteristicRoom = room - digits - (roundsUp ? int256(1) : int256(0));
        if (characteristicRoom >= 0) {
            checkAbsolute(signedCoefficient, exponent);
        } else {
            vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficient, exponent));
            this.log10UnroundedExternal(signedCoefficient, exponent);
        }
    }
}
