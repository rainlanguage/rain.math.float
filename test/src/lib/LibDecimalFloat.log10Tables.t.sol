// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, console2} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibLogTable, ALT_TABLE_FLAG} from "src/lib/table/LibLogTable.sol";
import {LibTestLogTables} from "test/lib/LibTestLogTables.sol";

/// `log10` over every four digit mantissa against the source tables and
/// against the source tables with derived mean differences swapped in for the
/// reference deviations (crates/tests/src/tables.rs). Errors are against
/// log10 in 1e36 fixed point, which is exact to well under 1e-30.
contract LibDecimalFloatLog10TablesTest is Test {
    using LibDecimalFloat for Float;

    uint256 constant ONE = 1e36;

    struct Swaps {
        bool worseOnly;
        uint256 deviations;
        uint256 swapped;
    }

    struct Stats {
        uint256 maxError;
        uint256 sumError;
        uint256 better;
        uint256 worse;
        uint256 maxRoundTrip;
    }

    /// 2 atanh((x - 1) / (x + 1)) = ln x, for x in [1, 2] scaled by ONE.
    function lnNearOne(uint256 x) internal pure returns (uint256) {
        uint256 z = (x - ONE) * ONE / (x + ONE);
        uint256 zz = z * z / ONE;
        uint256 term = z;
        uint256 sum = 0;
        for (uint256 k = 1; term > 0; k += 2) {
            sum += term / k;
            term = term * zz / ONE;
        }
        return 2 * sum;
    }

    function ln(uint256 n, uint256 lnTwo) internal pure returns (uint256) {
        uint256 k = 0;
        while (2 ** (k + 1) <= n) {
            k++;
        }
        return k * lnTwo + lnNearOne(n * ONE / 2 ** k);
    }

    function log10(uint256 n, uint256 lnTwo, uint256 lnTen) internal pure returns (uint256) {
        return ln(n, lnTwo) * ONE / lnTen;
    }

    function isWorse(uint256 row, bool second, uint256 digit) internal pure returns (bool) {
        return second
            && ((row == 13 && digit == 4)
                || (row == 10 && digit == 9)
                || (row == 16 && digit == 6)
                || (row == 19 && digit == 4)
                || (row == 14 && digit == 6));
    }

    /// The source small tables with the derived mean difference in place of
    /// every entry that deviates from it, or only of the five the PR found
    /// worse against the true log.
    function derivedTables(bool worseOnly, uint256[2] memory lnTwoTen)
        internal
        pure
        returns (uint8[10][90] memory, uint8[10][10] memory, Swaps memory)
    {
        uint16[10][90] memory main = LibLogTable.logTableDec();
        uint8[10][90] memory small = LibLogTable.logTableDecSmall();
        uint8[10][10] memory alt = LibLogTable.logTableDecSmallAlt();
        Swaps memory swaps;
        swaps.worseOnly = worseOnly;
        for (uint256 row = 0; row < 90; row++) {
            uint256 split = lineSplit(main[row]);
            uint256[10] memory derived = lineDerived(row, 0, split, lnTwoTen);
            swapLine(swaps, small[row], derived, row, false);
            if (split < 10) {
                derived = lineDerived(row, split, 10, lnTwoTen);
                swapLine(swaps, alt[row], derived, row, true);
            }
        }
        return (small, alt, swaps);
    }

    function lineSplit(uint16[10] memory mainRow) internal pure returns (uint256) {
        uint256 split = 10;
        for (uint256 col = 10; col > 0; col--) {
            if (mainRow[col - 1] & ALT_TABLE_FLAG != 0) {
                split = col - 1;
            }
        }
        return split;
    }

    /// Mean differences, rounded half up, on the line of log row `row`
    /// spanning columns `start..end`.
    function lineDerived(uint256 row, uint256 start, uint256 end, uint256[2] memory lnTwoTen)
        internal
        pure
        returns (uint256[10] memory)
    {
        uint256[10] memory derived;
        uint256 base = (10 + row) * 100;
        uint256 rise =
            log10(base + end * 10, lnTwoTen[0], lnTwoTen[1]) - log10(base + start * 10, lnTwoTen[0], lnTwoTen[1]);
        for (uint256 digit = 0; digit < 10; digit++) {
            derived[digit] = (digit * 1000 * rise / (end - start) + ONE / 2) / ONE;
        }
        return derived;
    }

    function swapLine(
        Swaps memory swaps,
        uint8[10] memory entries,
        uint256[10] memory derived,
        uint256 row,
        bool second
    ) internal pure {
        for (uint256 digit = 0; digit < 10; digit++) {
            if (derived[digit] != entries[digit]) {
                swaps.deviations++;
                if (!swaps.worseOnly || isWorse(10 + row, second, digit)) {
                    swaps.swapped++;
                    entries[digit] = uint8(derived[digit]);
                }
            }
        }
    }

    function toFixed(Float a) internal pure returns (uint256) {
        (uint256 value,) = a.toFixedDecimalLossy(36);
        return value;
    }

    function absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    /// The largest |a / (a ^ b) ^ (1 / b) - 1| over the round trips
    /// LibDecimalFloatPowTest.testRoundTripSimple checks, scaled by ONE.
    function maxRoundTrip(address tables) internal view returns (uint256) {
        uint256 worst = 0;
        int256[4][9] memory cases = [
            [int256(5), 0, 2, 0],
            [int256(5), 0, 3, 0],
            [int256(50), 0, 40, 0],
            [int256(5), -1, 3, -1],
            [int256(5), -1, 2, -1],
            [int256(5), 10, 3, 5],
            [int256(5), -1, 100, 0],
            [int256(7721), 0, -1, -2],
            [int256(4157), 0, -1, -2]
        ];
        for (uint256 i = 0; i < cases.length; i++) {
            Float a = LibDecimalFloat.packLossless(cases[i][0], cases[i][1]);
            Float b = LibDecimalFloat.packLossless(cases[i][2], cases[i][3]);
            Float roundTrip = a.pow(b, tables).pow(b.inv(), tables);
            uint256 diff = toFixed(a.div(roundTrip).sub(LibDecimalFloat.FLOAT_ONE).abs());
            if (diff > worst) {
                worst = diff;
            }
        }
        return worst;
    }

    function measure(address tables, uint256[] memory truth, uint256[] memory referenceErrors)
        internal
        view
        returns (Stats memory, uint256[] memory)
    {
        Stats memory stats;
        uint256[] memory errors = new uint256[](truth.length);
        for (uint256 i = 0; i < truth.length; i++) {
            uint256 n = 1000 + i;
            uint256 lookupError = absDiff(
                toFixed(LibDecimalFloat.fromFixedDecimalLosslessPacked(n, 0).log10(tables)), 3 * ONE + truth[i]
            );
            errors[i] = lookupError;
            stats.sumError += lookupError;
            if (lookupError > stats.maxError) {
                stats.maxError = lookupError;
            }
            if (referenceErrors.length > 0) {
                if (lookupError < referenceErrors[i]) {
                    stats.better++;
                } else if (lookupError > referenceErrors[i]) {
                    stats.worse++;
                }
            }
        }
        stats.maxRoundTrip = maxRoundTrip(tables);
        return (stats, errors);
    }

    function report(string memory name, Stats memory stats, uint256 count) internal pure {
        console2.log(name);
        console2.log("  max error  1e-36:", stats.maxError);
        console2.log("  mean error 1e-36:", stats.sumError / count);
        console2.log("  better / worse  :", stats.better, stats.worse);
        console2.log("  round trip 1e-36:", stats.maxRoundTrip);
    }

    function testLog10TableVariants() external {
        uint256 lnTwo = lnNearOne(2 * ONE);
        uint256 lnTen = 3 * lnTwo + lnNearOne(ONE * 5 / 4);

        // log10(n / 1000) for n = 1000..9999.
        uint256[] memory truth = new uint256[](9000);
        for (uint256 i = 0; i < truth.length; i++) {
            truth[i] = log10(1000 + i, lnTwo, lnTen) - 3 * ONE;
        }

        (Stats memory referenceStats, uint256[] memory referenceErrors) =
            measure(LibTestLogTables.deploy(), truth, new uint256[](0));
        report("reference", referenceStats, truth.length);
        assertLe(referenceStats.maxError, 1.3444e32, "reference max");
        assertGe(referenceStats.maxError, 1.3443e32, "reference max");

        (uint8[10][90] memory small, uint8[10][10] memory alt, Swaps memory swaps) = derivedTables(true, [lnTwo, lnTen]);
        assertEq(swaps.deviations, 28, "deviations");
        assertEq(swaps.swapped, 5, "worse swapped");
        (Stats memory worseFive,) = measure(LibTestLogTables.deploy(small, alt), truth, referenceErrors);
        report("derived, 5 worse entries", worseFive, truth.length);
        assertEq(worseFive.maxError, referenceStats.maxError, "worse five max");
        assertLt(worseFive.sumError, referenceStats.sumError, "worse five mean");
        assertEq(worseFive.better, 15, "worse five better");
        assertEq(worseFive.worse, 11, "worse five worse");
        assertEq(worseFive.maxRoundTrip, referenceStats.maxRoundTrip, "worse five round trip");

        (small, alt, swaps) = derivedTables(false, [lnTwo, lnTen]);
        assertEq(swaps.swapped, 28, "all swapped");
        (Stats memory allDerived,) = measure(LibTestLogTables.deploy(small, alt), truth, referenceErrors);
        report("derived, all 28", allDerived, truth.length);
        assertLe(allDerived.maxError, 1.1946e32, "all derived max");
        assertGe(allDerived.maxError, 1.1945e32, "all derived max");
        assertGt(allDerived.sumError, referenceStats.sumError, "all derived mean");
        assertEq(allDerived.better, 61, "all derived better");
        assertEq(allDerived.worse, 88, "all derived worse");
        assertEq(allDerived.maxRoundTrip, referenceStats.maxRoundTrip, "all derived round trip");
    }
}
