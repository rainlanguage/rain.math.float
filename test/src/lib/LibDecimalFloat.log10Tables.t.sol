// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, console2} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibLogTable, ALT_TABLE_FLAG} from "src/lib/table/LibLogTable.sol";
import {LibTestLogTables} from "test/lib/LibTestLogTables.sol";
import {LibTestTranscendental} from "test/lib/LibTestTranscendental.sol";
import {LibTestPrecision} from "test/lib/LibTestPrecision.sol";

/// `log10` over every four digit mantissa against the shipped tables, the
/// published reference tables, and variants with derived mean differences
/// swapped in for the reference deviations (crates/tests/src/tables.rs).
/// Errors are against log10 in 1e36 fixed point, which is exact to well under
/// 1e-30.
contract LibDecimalFloatLog10TablesTest is Test {
    using LibDecimalFloat for Float;

    uint256 constant ONE = 1e36;

    /// A small table entry that differs from its derived mean difference. Its
    /// line spans columns `start..end`.
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

    function log10(uint256 n) internal pure returns (uint256) {
        return LibTestTranscendental.log10Scaled(n * ONE);
    }

    /// The published reference small tables: the shipped ones with the
    /// reference value back at the 14 entries where the shipped table takes
    /// the derived mean difference.
    function publishedTables() internal pure returns (uint8[10][90] memory small, uint8[10][10] memory alt) {
        small = LibLogTable.logTableDecSmall();
        alt = LibLogTable.logTableDecSmallAlt();
        alt[0][9] = 37;
        alt[3][2] = 7;
        alt[3][4] = 12;
        alt[4][6] = 17;
        small[6][5] = 14;
        small[6][8] = 22;
        alt[6][6] = 15;
        alt[8][5] = 11;
        small[9][6] = 13;
        alt[9][3] = 6;
        alt[9][4] = 8;
        alt[9][8] = 17;
        alt[9][9] = 19;
        small[64][6] = 4;
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

    function deviations(uint8[10][90] memory small, uint8[10][10] memory alt)
        internal
        pure
        returns (Deviation[] memory)
    {
        uint16[10][90] memory main = LibLogTable.logTableDec();
        Deviation[] memory found = new Deviation[](100);
        uint256 count = 0;
        for (uint256 row = 0; row < 90; row++) {
            uint256 split = lineSplit(main[row]);
            count = collectLine(found, count, small[row], row, false, split);
            if (split < 10) {
                count = collectLine(found, count, alt[row], row, true, split);
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
        uint256 split
    ) internal pure returns (uint256) {
        uint256 start = second ? split : 0;
        uint256 end = second ? 10 : split;
        uint256[10] memory derived = lineDerived(row, start, end);
        for (uint256 digit = 0; digit < 10; digit++) {
            if (derived[digit] != entries[digit]) {
                // forge-lint: disable-next-line(unsafe-typecast)
                found[count++] = Deviation(row, second, digit, start, end, uint8(derived[digit]));
            }
        }
        return count;
    }

    /// The published small tables with the derived value in place of each
    /// deviation `picked` selects.
    function swappedTables(Deviation[] memory found, bool[] memory picked)
        internal
        pure
        returns (uint8[10][90] memory, uint8[10][10] memory)
    {
        (uint8[10][90] memory small, uint8[10][10] memory alt) = publishedTables();
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
    function lineDerived(uint256 row, uint256 start, uint256 end) internal pure returns (uint256[10] memory) {
        uint256[10] memory derived;
        uint256 base = (10 + row) * 100;
        uint256 rise = log10(base + end * 10) - log10(base + start * 10);
        for (uint256 digit = 0; digit < 10; digit++) {
            derived[digit] = (digit * 1000 * rise / (end - start) + ONE / 2) / ONE;
        }
        return derived;
    }

    /// Max and summed error over the mantissas that read the entry. A 4-digit
    /// mantissa reads exactly one small entry, so the all-derived errors there
    /// are the derived value's alone.
    function lineErrors(Deviation memory deviation, uint256[] memory errors)
        internal
        pure
        returns (uint256 maxError, uint256 sumError)
    {
        for (uint256 col = deviation.start; col < deviation.end; col++) {
            uint256 i = deviation.row * 100 + col * 10 + deviation.digit;
            sumError += errors[i];
            if (errors[i] > maxError) {
                maxError = errors[i];
            }
        }
    }

    /// One of max and summed error is lower and the other is not higher.
    function derivedImproves(
        Deviation memory deviation,
        uint256[] memory referenceErrors,
        uint256[] memory derivedErrors
    ) internal pure returns (bool) {
        (uint256 referenceMax, uint256 referenceSum) = lineErrors(deviation, referenceErrors);
        (uint256 derivedMax, uint256 derivedSum) = lineErrors(deviation, derivedErrors);
        return (derivedMax <= referenceMax && derivedSum < referenceSum)
            || (derivedMax < referenceMax && derivedSum <= referenceSum);
    }

    function derivedLowersMax(
        Deviation memory deviation,
        uint256[] memory referenceErrors,
        uint256[] memory derivedErrors
    ) internal pure returns (bool) {
        (uint256 referenceMax,) = lineErrors(deviation, referenceErrors);
        (uint256 derivedMax,) = lineErrors(deviation, derivedErrors);
        return derivedMax < referenceMax;
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

    function sameTables(
        uint8[10][90] memory small,
        uint8[10][10] memory alt,
        uint8[10][90] memory otherSmall,
        uint8[10][10] memory otherAlt
    ) internal pure returns (bool) {
        return keccak256(abi.encode(small, alt)) == keccak256(abi.encode(otherSmall, otherAlt));
    }

    struct Context {
        uint256[] truth;
        Deviation[] found;
        Stats published;
        uint256[] publishedErrors;
        uint256[] derivedErrors;
    }

    function checkPublished(Context memory context) internal {
        (uint8[10][90] memory small, uint8[10][10] memory alt) = publishedTables();
        (context.published, context.publishedErrors) =
            measure(LibTestLogTables.deploy(small, alt), context.truth, new uint256[](0));
        report("published", context.published, context.truth.length);
        assertLe(context.published.maxError, 1.3444e32, "published max");
        assertGe(context.published.maxError, 1.3443e32, "published max");
        assertLe(context.published.sumError / context.truth.length, 3.2937e31, "published mean");
        assertGe(context.published.sumError / context.truth.length, 3.2936e31, "published mean");
        context.found = deviations(small, alt);
        assertEq(context.found.length, 28, "published deviations");
    }

    function checkShipped(Context memory context) internal returns (Stats memory shipped) {
        (shipped,) = measure(LibTestLogTables.deploy(), context.truth, context.publishedErrors);
        report("shipped", shipped, context.truth.length);
        assertLe(shipped.maxError, 1.1943e32, "shipped max");
        assertGe(shipped.maxError, 1.1942e32, "shipped max");
        assertLe(shipped.sumError / context.truth.length, 3.2956e31, "shipped mean");
        assertGt(shipped.sumError, context.published.sumError, "shipped mean");
        assertGe(shipped.sumError / context.truth.length, 3.2955e31, "shipped mean");
        assertEq(shipped.better, 31, "shipped better");
        assertEq(shipped.worse, 45, "shipped worse");
        assertEq(shipped.maxRoundTrip, context.published.maxRoundTrip, "shipped round trip");
        assertEq(
            deviations(LibLogTable.logTableDecSmall(), LibLogTable.logTableDecSmallAlt()).length,
            14,
            "shipped deviations"
        );

        // The four digit lookup bound holds for the shipped tables and not for
        // the published ones.
        assertLt(shipped.maxError, LibTestPrecision.LOG10_TABLE_MAX_ERROR, "shipped within bound");
        assertGt(context.published.maxError, LibTestPrecision.LOG10_TABLE_MAX_ERROR, "published within bound");
    }

    function checkWorseFive(Context memory context) internal {
        Deviation[] memory found = context.found;
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
        (Stats memory worseFive,) = measure(LibTestLogTables.deploy(small, alt), context.truth, context.publishedErrors);
        report("derived, 5 worse entries", worseFive, context.truth.length);
        assertEq(worseFive.maxError, context.published.maxError, "worse five max");
        assertLt(worseFive.sumError, context.published.sumError, "worse five mean");
        assertEq(worseFive.better, 15, "worse five better");
        assertEq(worseFive.worse, 11, "worse five worse");
        assertEq(worseFive.maxRoundTrip, context.published.maxRoundTrip, "worse five round trip");
    }

    function checkAllDerived(Context memory context) internal {
        bool[] memory picked = new bool[](context.found.length);
        for (uint256 i = 0; i < picked.length; i++) {
            picked[i] = true;
        }
        (uint8[10][90] memory small, uint8[10][10] memory alt) = swappedTables(context.found, picked);
        Stats memory allDerived;
        (allDerived, context.derivedErrors) =
            measure(LibTestLogTables.deploy(small, alt), context.truth, context.publishedErrors);
        report("derived, all 28", allDerived, context.truth.length);
        assertLe(allDerived.maxError, 1.1946e32, "all derived max");
        assertGe(allDerived.maxError, 1.1945e32, "all derived max");
        assertGt(allDerived.sumError, context.published.sumError, "all derived mean");
        assertEq(allDerived.better, 61, "all derived better");
        assertEq(allDerived.worse, 88, "all derived worse");
        assertEq(allDerived.maxRoundTrip, context.published.maxRoundTrip, "all derived round trip");
    }

    function checkPerEntryBest(Context memory context) internal {
        Deviation[] memory found = context.found;
        bool[] memory picked = new bool[](found.length);
        uint256[5] memory expectedPicks =
            [key(10, true, 9), key(13, true, 4), key(14, true, 6), key(16, true, 6), key(19, true, 4)];
        console2.log("per entry best, derived picked at row * 100 + alt * 10 + digit:");
        uint256 count = 0;
        for (uint256 i = 0; i < found.length; i++) {
            picked[i] = derivedImproves(found[i], context.publishedErrors, context.derivedErrors);
            if (picked[i]) {
                uint256 pick = key(10 + found[i].row, found[i].second, found[i].digit);
                console2.log(pick);
                assertEq(pick, expectedPicks[count], "per entry best pick");
                count++;
            }
        }
        assertEq(count, expectedPicks.length, "per entry best picks");
        (uint8[10][90] memory small, uint8[10][10] memory alt) = swappedTables(found, picked);
        (Stats memory best,) = measure(LibTestLogTables.deploy(small, alt), context.truth, context.publishedErrors);
        report("per entry best", best, context.truth.length);
        assertEq(best.maxError, context.published.maxError, "per entry best max");
        assertLe(best.sumError / context.truth.length, 3.2891e31, "per entry best mean");
        assertGe(best.sumError / context.truth.length, 3.289e31, "per entry best mean");
        assertLt(best.sumError, context.published.sumError, "per entry best mean");
        assertEq(best.better, 15, "per entry best better");
        assertEq(best.worse, 11, "per entry best worse");
        assertEq(best.maxRoundTrip, context.published.maxRoundTrip, "per entry best round trip");
    }

    /// The shipped tables are exactly the published ones with the derived
    /// value at every deviation that lowers max error on its own line.
    function checkMaxPicks(Context memory context) internal pure {
        Deviation[] memory found = context.found;
        bool[] memory picked = new bool[](found.length);
        uint256[14] memory shippedPicks = [
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
        uint256 count = 0;
        for (uint256 i = 0; i < found.length; i++) {
            picked[i] = derivedLowersMax(found[i], context.publishedErrors, context.derivedErrors);
            if (picked[i]) {
                assertEq(key(10 + found[i].row, found[i].second, found[i].digit), shippedPicks[count], "max pick");
                count++;
            }
        }
        assertEq(count, shippedPicks.length, "max picks");
        (uint8[10][90] memory small, uint8[10][10] memory alt) = swappedTables(found, picked);
        assertTrue(
            sameTables(small, alt, LibLogTable.logTableDecSmall(), LibLogTable.logTableDecSmallAlt()),
            "shipped is the max picks"
        );
    }

    function testLog10TableVariants() external {
        Context memory context;
        // log10(n / 1000) for n = 1000..9999.
        context.truth = new uint256[](9000);
        for (uint256 i = 0; i < context.truth.length; i++) {
            context.truth[i] = LibTestTranscendental.log10Scaled((1000 + i) * 1e33);
        }
        checkPublished(context);
        Stats memory shipped = checkShipped(context);
        checkWorseFive(context);
        checkAllDerived(context);
        checkPerEntryBest(context);
        checkMaxPicks(context);
        assertLt(shipped.maxRoundTrip, LibTestPrecision.POW_ROUND_TRIP_LIMIT, "shipped diffLimit");
    }
}
