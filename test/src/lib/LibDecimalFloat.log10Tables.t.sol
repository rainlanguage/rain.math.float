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

    /// A source small table entry that differs from its derived mean
    /// difference. Its line spans columns `start..end`.
    struct Deviation {
        uint256 row;
        bool second;
        uint256 digit;
        uint256 start;
        uint256 end;
        uint8 derived;
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

    function isWorse(Deviation memory deviation) internal pure returns (bool) {
        uint256 row = 10 + deviation.row;
        uint256 digit = deviation.digit;
        return deviation.second
            && ((row == 13 && digit == 4)
                || (row == 10 && digit == 9)
                || (row == 16 && digit == 6)
                || (row == 19 && digit == 4)
                || (row == 14 && digit == 6));
    }

    function key(uint256 row, bool second, uint256 digit) internal pure returns (uint256) {
        return row * 100 + (second ? 10 : 0) + digit;
    }

    function deviations(uint256[2] memory lnTwoTen) internal pure returns (Deviation[] memory) {
        uint16[10][90] memory main = LibLogTable.logTableDec();
        uint8[10][90] memory small = LibLogTable.logTableDecSmall();
        uint8[10][10] memory alt = LibLogTable.logTableDecSmallAlt();
        Deviation[] memory found = new Deviation[](100);
        uint256 count = 0;
        for (uint256 row = 0; row < 90; row++) {
            uint256 split = lineSplit(main[row]);
            count = collectLine(found, count, small[row], row, false, split, lnTwoTen);
            if (split < 10) {
                count = collectLine(found, count, alt[row], row, true, split, lnTwoTen);
            }
        }
        assembly ("memory-safe") {
            mstore(found, count)
        }
        return found;
    }

    function collectLine(
        Deviation[] memory found,
        uint256 count,
        uint8[10] memory entries,
        uint256 row,
        bool second,
        uint256 split,
        uint256[2] memory lnTwoTen
    ) internal pure returns (uint256) {
        uint256 start = second ? split : 0;
        uint256 end = second ? 10 : split;
        uint256[10] memory derived = lineDerived(row, start, end, lnTwoTen);
        for (uint256 digit = 0; digit < 10; digit++) {
            if (derived[digit] != entries[digit]) {
                // forge-lint: disable-next-line(unsafe-typecast)
                found[count++] = Deviation(row, second, digit, start, end, uint8(derived[digit]));
            }
        }
        return count;
    }

    /// The source small tables with the derived value in place of each
    /// deviation `picked` selects.
    function swappedTables(Deviation[] memory found, bool[] memory picked)
        internal
        pure
        returns (uint8[10][90] memory, uint8[10][10] memory)
    {
        uint8[10][90] memory small = LibLogTable.logTableDecSmall();
        uint8[10][10] memory alt = LibLogTable.logTableDecSmallAlt();
        for (uint256 i = 0; i < found.length; i++) {
            if (picked[i]) {
                Deviation memory deviation = found[i];
                if (deviation.second) {
                    alt[deviation.row][deviation.digit] = deviation.derived;
                } else {
                    small[deviation.row][deviation.digit] = deviation.derived;
                }
            }
        }
        return (small, alt);
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

    /// Lower max error over the mantissas that read the entry, else equal max
    /// and lower summed error. A 4-digit mantissa reads exactly one small
    /// entry, so the all-derived errors there are the derived value's alone.
    function derivedImproves(
        Deviation memory deviation,
        uint256[] memory referenceErrors,
        uint256[] memory derivedErrors
    ) internal pure returns (bool) {
        uint256 referenceMax = 0;
        uint256 referenceSum = 0;
        uint256 derivedMax = 0;
        uint256 derivedSum = 0;
        for (uint256 col = deviation.start; col < deviation.end; col++) {
            uint256 i = deviation.row * 100 + col * 10 + deviation.digit;
            referenceSum += referenceErrors[i];
            derivedSum += derivedErrors[i];
            if (referenceErrors[i] > referenceMax) {
                referenceMax = referenceErrors[i];
            }
            if (derivedErrors[i] > derivedMax) {
                derivedMax = derivedErrors[i];
            }
        }
        return derivedMax < referenceMax || (derivedMax == referenceMax && derivedSum < referenceSum);
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

        Deviation[] memory found = deviations([lnTwo, lnTen]);
        assertEq(found.length, 28, "deviations");
        bool[] memory picked = new bool[](found.length);
        uint256 count = 0;
        for (uint256 i = 0; i < found.length; i++) {
            picked[i] = isWorse(found[i]);
            if (picked[i]) {
                count++;
            }
        }
        assertEq(count, 5, "worse swapped");
        (uint8[10][90] memory small, uint8[10][10] memory alt) = swappedTables(found, picked);
        (Stats memory worseFive,) = measure(LibTestLogTables.deploy(small, alt), truth, referenceErrors);
        report("derived, 5 worse entries", worseFive, truth.length);
        assertEq(worseFive.maxError, referenceStats.maxError, "worse five max");
        assertLt(worseFive.sumError, referenceStats.sumError, "worse five mean");
        assertEq(worseFive.better, 15, "worse five better");
        assertEq(worseFive.worse, 11, "worse five worse");
        assertEq(worseFive.maxRoundTrip, referenceStats.maxRoundTrip, "worse five round trip");

        for (uint256 i = 0; i < found.length; i++) {
            picked[i] = true;
        }
        (small, alt) = swappedTables(found, picked);
        (Stats memory allDerived, uint256[] memory derivedErrors) =
            measure(LibTestLogTables.deploy(small, alt), truth, referenceErrors);
        report("derived, all 28", allDerived, truth.length);
        assertLe(allDerived.maxError, 1.1946e32, "all derived max");
        assertGe(allDerived.maxError, 1.1945e32, "all derived max");
        assertGt(allDerived.sumError, referenceStats.sumError, "all derived mean");
        assertEq(allDerived.better, 61, "all derived better");
        assertEq(allDerived.worse, 88, "all derived worse");
        assertEq(allDerived.maxRoundTrip, referenceStats.maxRoundTrip, "all derived round trip");

        uint256[14] memory expectedPicks = [
            key(10, true, 9),
            key(13, true, 2),
            key(13, true, 4),
            key(14, true, 6),
            key(16, false, 5),
            key(16, false, 8),
            key(16, true, 6),
            key(18, true, 5),
            key(19, false, 6),
            key(19, true, 3),
            key(19, true, 4),
            key(19, true, 8),
            key(19, true, 9),
            key(74, false, 6)
        ];
        console2.log("per entry best, derived picked at row * 100 + alt * 10 + digit:");
        count = 0;
        for (uint256 i = 0; i < found.length; i++) {
            picked[i] = derivedImproves(found[i], referenceErrors, derivedErrors);
            if (picked[i]) {
                uint256 pick = key(10 + found[i].row, found[i].second, found[i].digit);
                console2.log(pick);
                assertEq(pick, expectedPicks[count], "per entry best pick");
                count++;
            }
        }
        assertEq(count, expectedPicks.length, "per entry best picks");
        (small, alt) = swappedTables(found, picked);
        (Stats memory best,) = measure(LibTestLogTables.deploy(small, alt), truth, referenceErrors);
        report("per entry best", best, truth.length);
        assertLe(best.maxError, 1.1943e32, "per entry best max");
        assertGe(best.maxError, 1.1942e32, "per entry best max");
        assertLe(best.sumError / truth.length, 3.2956e31, "per entry best mean");
        assertGe(best.sumError / truth.length, 3.2955e31, "per entry best mean");
        assertGt(best.sumError, referenceStats.sumError, "per entry best mean");
        assertEq(best.better, 31, "per entry best better");
        assertEq(best.worse, 45, "per entry best worse");
        assertEq(best.maxRoundTrip, referenceStats.maxRoundTrip, "per entry best round trip");
        // LibDecimalFloatPowTest.testRoundTripSimple diffLimit.
        assertLt(best.maxRoundTrip, 0.09e36, "per entry best diffLimit");
    }
}
