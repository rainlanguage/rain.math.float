//! The log tables `LibLogTable` ships, read through the harness, against
//! derivations of the published four-figure tables.
#![allow(clippy::needless_range_loop)]

use crate::evm::{self, TestDecimalFloatHarness as H};

/// `ALT_TABLE_FLAG` as used in LibLogTable.sol: bit 15 of a uint16.
const ALT_TABLE_FLAG: u16 = 0x8000;

#[test]
fn alt_table_flag_is_the_library_flag() {
    assert_eq!(alt_table_flag(), ALT_TABLE_FLAG);
}

/// Generate the main log table without ALT_TABLE_FLAG: uint16[10][90].
///
/// Row r (0-89) and column c (0-9) represent the 3-digit mantissa prefix
/// (10+r) and third digit c, so the looked-up number is
/// n = (10+r)*100 + c*10. The value is round((log10(n) - 3) * 10000).
fn generate_log_table() -> [[u16; 10]; 90] {
    let mut table = [[0u16; 10]; 90];
    for (row, table_row) in table.iter_mut().enumerate() {
        for (col, entry) in table_row.iter_mut().enumerate() {
            let n = ((10 + row) * 100 + col * 10) as f64;
            *entry = ((n.log10() - 3.0) * 10000.0).round() as u16;
        }
    }
    table
}

/// Generate the antilog table: uint16[10][100].
///
/// The full antilog index range is 0-9999 (ANTILOG_IDX_CARDINALITY).
/// The main table has 1000 entries (100 rows × 10 cols), one per group
/// of 10 consecutive indices. Flattened entry k corresponds to indices
/// k*10 through k*10+9. Value = round(10^(k*10/10000) * 1000).
fn generate_antilog_table() -> [[u16; 10]; 100] {
    let mut table = [[0u16; 10]; 100];
    for (row, table_row) in table.iter_mut().enumerate() {
        for (col, entry) in table_row.iter_mut().enumerate() {
            let k = row * 10 + col;
            *entry = (10.0_f64.powf((k * 10) as f64 / 10000.0) * 1000.0).round() as u16;
        }
    }
    table
}

/// Verify the main log table entries are within ±1 of the true value.
/// The Solidity tables are transcribed from a published 4-figure log
/// table reference and may use rounding conventions that differ from
/// IEEE 754 f64, so we check proximity rather than exact equality.
#[test]
fn test_log_table_accuracy() {
    let table = log_table_dec();
    for row in 0..90 {
        for col in 0..10 {
            let n = ((10 + row) * 100 + col * 10) as f64;
            let expected = ((n.log10() - 3.0) * 10000.0).round() as i32;
            let actual = (table[row][col] & !ALT_TABLE_FLAG) as i32;
            assert!(
                (actual - expected).abs() <= 1,
                "log table [{row}][{col}]: n={n}, expected={expected}, actual={actual}, diff={}",
                actual - expected
            );
        }
    }
}

/// Verify the main antilog table entries are within ±1 of the true value.
#[test]
fn test_antilog_table_accuracy() {
    let table = anti_log_table_dec();
    for row in 0..100 {
        for col in 0..10 {
            let k = row * 10 + col;
            let expected = (10.0_f64.powf((k * 10) as f64 / 10000.0) * 1000.0).round() as i32;
            let actual = table[row][col] as i32;
            assert!(
                (actual - expected).abs() <= 1,
                "antilog table [{row}][{col}]: k={k}, expected={expected}, actual={actual}, diff={}",
                actual - expected
            );
        }
    }
}

/// Verify that main + small gives a value close to the true log10
/// for every 4-digit number 1000-9999.
#[test]
fn test_log_lookup_accuracy() {
    let main = log_table_dec();
    let small = log_table_dec_small();
    let small_alt = log_table_dec_small_alt();
    for n in 1000..10000_usize {
        let row = n / 10 - 100;
        let _col = (n / 10) % 10;
        let d = n % 10;
        let main_row = row / 10;
        let main_col = row % 10;

        let main_entry = main[main_row][main_col];
        let main_val = (main_entry & !ALT_TABLE_FLAG) as i32;
        let use_alt = main_entry & ALT_TABLE_FLAG != 0;
        let small_val = if use_alt {
            small_alt[main_row][d] as i32
        } else {
            small[main_row][d] as i32
        };
        let table_result = main_val + small_val;
        let true_val = ((n as f64).log10() - 3.0) * 10000.0;

        // The lookup should be within 2 of the true value (main has
        // ±1 error, small has ±1 error).
        assert!(
            (table_result as f64 - true_val).abs() < 2.5,
            "log lookup for n={n}: table={table_result}, true={true_val:.2}, diff={:.2}",
            table_result as f64 - true_val
        );
    }
}

/// Verify that main + small gives a value close to the true antilog
/// for every index 0-9999.
#[test]
fn test_antilog_lookup_accuracy() {
    let main = anti_log_table_dec();
    let small = anti_log_table_dec_small();
    for idx in 0..10000_usize {
        let main_k = idx / 10;
        let main_row = main_k / 10;
        let main_col = main_k % 10;
        let main_val = main[main_row][main_col] as i32;

        let small_row = idx / 100;
        let small_col = idx % 10;
        let small_val = small[small_row][small_col] as i32;

        let table_result = main_val + small_val;
        let true_val = 10.0_f64.powf(idx as f64 / 10000.0) * 1000.0;

        assert!(
            (table_result as f64 - true_val).abs() < 2.5,
            "antilog lookup for idx={idx}: table={table_result}, true={true_val:.2}, diff={:.2}",
            table_result as f64 - true_val
        );
    }
}

/// Verify that the main antilog table entries exactly match
/// round(10^(k*10/10000) * 1000).
#[test]
fn test_antilog_table_exact() {
    let generated = generate_antilog_table();
    let solidity = anti_log_table_dec();
    for row in 0..100 {
        for col in 0..10 {
            assert_eq!(
                generated[row][col], solidity[row][col],
                "antilog table mismatch at [{row}][{col}]: generated={}, solidity={}",
                generated[row][col], solidity[row][col]
            );
        }
    }
}

/// The small tables are the published mean differences: the entry for
/// fourth digit d on a printed line is d tenths of the mean tabular
/// difference across that line, rounded half up.
///
/// Log rows 10-19 print as two lines, the second starting at the first
/// column flagged ALT_TABLE_FLAG and reading its mean differences from the
/// alt small table. Every other log row, and every antilog row, is one line.
fn line_split(main: &[[u16; 10]; 90], row: usize) -> usize {
    let split = main[row]
        .iter()
        .position(|entry| entry & ALT_TABLE_FLAG != 0)
        .unwrap_or(10);
    assert!(
        main[row][split..]
            .iter()
            .all(|entry| entry & ALT_TABLE_FLAG != 0),
        "log row {}: flagged columns are not a suffix",
        10 + row
    );
    split
}

/// Mean difference for `digit` on the line of log row `row` spanning
/// columns `start..end`, in units of 1e-4 of log10.
fn log_mean_difference(row: usize, start: usize, end: usize, digit: usize) -> f64 {
    let base = ((10 + row) * 100) as f64;
    let rise = (base + (end * 10) as f64).log10() - (base + (start * 10) as f64).log10();
    digit as f64 * rise * 1000.0 / (end - start) as f64
}

/// Mean difference for `digit` on antilog row `row` (.00-.99), in units of
/// the four-figure antilog.
fn antilog_mean_difference(row: usize, digit: usize) -> f64 {
    let rise = 10f64.powf((row + 1) as f64 / 100.0) - 10f64.powf(row as f64 / 100.0);
    digit as f64 * rise * 10.0
}

/// Rounds half up. Every mean difference is at least 3e-4 from a half and
/// f64 error here is below 1e-12, so refusing anything within 1e-6 of a half
/// makes this the exact rounding.
fn round_certified(value: f64) -> u8 {
    let margin = (value - value.floor() - 0.5).abs();
    assert!(
        margin > 1e-6,
        "{value} is too close to a half to round from f64"
    );
    value.round() as u8
}

/// First column of the second printed line of log rows 10-19, read from the
/// reference PDF.
const SECOND_LINE_STARTS: [usize; 10] = [5, 5, 6, 5, 4, 6, 5, 6, 5, 5];

/// Entries where the shipped table holds the other integer that brackets the
/// derived mean difference, as (log row, second line, digit). They are the
/// published reference's values. The reference is not one formula: no single
/// mean difference reproduces log row 12's first line or row 13's second line.
const DEVIATIONS: [(usize, bool, usize); 14] = [
    (10, false, 2),
    (10, false, 6),
    (11, true, 5),
    (12, false, 1),
    (13, true, 3),
    (13, true, 9),
    (14, true, 7),
    (14, true, 8),
    (14, true, 9),
    (17, true, 8),
    (18, false, 4),
    (18, false, 7),
    (18, true, 8),
    (19, false, 2),
];

/// Entries where the shipped table takes the derived mean difference over the
/// published reference, as (log row, second line, digit, published value).
const PUBLISHED: [(usize, bool, usize, u8); 14] = [
    (10, true, 9, 37),
    (13, true, 2, 7),
    (13, true, 4, 12),
    (14, true, 6, 17),
    (16, false, 5, 14),
    (16, false, 8, 22),
    (16, true, 6, 15),
    (18, true, 5, 11),
    (19, false, 6, 13),
    (19, true, 3, 6),
    (19, true, 4, 8),
    (19, true, 8, 17),
    (19, true, 9, 19),
    (74, false, 6, 4),
];

/// The derived mean difference for (log row, second line, digit).
fn derived_entry(main: &[[u16; 10]; 90], row: usize, second: bool, digit: usize) -> u8 {
    let split = line_split(main, row - 10);
    let (start, end) = if second { (split, 10) } else { (0, split) };
    round_certified(log_mean_difference(row - 10, start, end, digit))
}

/// Every small log entry that is not its derived mean difference, asserting
/// each is the other integer bracketing it.
fn deviations(
    main: &[[u16; 10]; 90],
    small: &[[u8; 10]; 90],
    alt: &[[u8; 10]; 10],
) -> Vec<(usize, bool, usize)> {
    let mut deviations = Vec::new();
    for row in 0..90 {
        let split = line_split(main, row);
        let mut lines = vec![(false, 0, split, small[row])];
        if split < 10 {
            lines.push((true, split, 10, alt[row]));
        }
        for (second, start, end, entries) in lines {
            for digit in 0..10 {
                let exact = log_mean_difference(row, start, end, digit);
                let derived = round_certified(exact);
                let entry = entries[digit];
                if entry != derived {
                    assert!(
                        (entry as f64 - exact).abs() < 1.0,
                        "log row {} second line {second} digit {digit}: entry {entry}, exact {exact}",
                        10 + row
                    );
                    deviations.push((10 + row, second, digit));
                }
            }
        }
    }
    deviations
}

/// Every small log entry is its derived mean difference, or is listed in
/// DEVIATIONS and is the other integer bracketing it.
#[test]
fn test_log_table_small_derivation() {
    let main = log_table_dec();
    let small = log_table_dec_small();
    let alt = log_table_dec_small_alt();
    for row in 0..90 {
        let expected = if row < 10 {
            SECOND_LINE_STARTS[row]
        } else {
            10
        };
        assert_eq!(
            line_split(&main, row),
            expected,
            "log row {}: line split",
            10 + row
        );
    }
    assert_eq!(deviations(&main, &small, &alt), DEVIATIONS);
}

/// The shipped small tables with `entries` set to `value`.
fn with_entries(
    small: &[[u8; 10]; 90],
    alt: &[[u8; 10]; 10],
    entries: &[(usize, bool, usize, u8)],
) -> ([[u8; 10]; 90], [[u8; 10]; 10]) {
    let (mut small, mut alt) = (*small, *alt);
    for &(row, second, digit, value) in entries {
        if second {
            alt[row - 10][digit] = value;
        } else {
            small[row - 10][digit] = value;
        }
    }
    (small, alt)
}

fn published_tables() -> ([[u8; 10]; 90], [[u8; 10]; 10]) {
    with_entries(
        &log_table_dec_small(),
        &log_table_dec_small_alt(),
        &PUBLISHED,
    )
}

/// |main + small - log10| over every mantissa 1000-9999, in units of log10.
/// A four digit mantissa reads one main and one small entry, no
/// interpolation, so this is log10's error there.
fn lookup_errors(main: &[[u16; 10]; 90], small: &[[u8; 10]; 90], alt: &[[u8; 10]; 10]) -> Vec<f64> {
    (1000..10000_usize)
        .map(|n| {
            let row = n / 100 - 10;
            let entry = main[row][(n / 10) % 10];
            let fine = if entry & ALT_TABLE_FLAG != 0 {
                alt[row][n % 10]
            } else {
                small[row][n % 10]
            };
            let lookup = ((entry & !ALT_TABLE_FLAG) as f64 + fine as f64) / 10000.0;
            (lookup - ((n as f64).log10() - 3.0)).abs()
        })
        .collect()
}

struct Stats {
    max: f64,
    mean: f64,
    better: usize,
    worse: usize,
}

fn stats(errors: &[f64], reference: &[f64]) -> Stats {
    Stats {
        max: errors.iter().cloned().fold(0.0, f64::max),
        mean: errors.iter().sum::<f64>() / errors.len() as f64,
        better: errors.iter().zip(reference).filter(|(e, r)| e < r).count(),
        worse: errors.iter().zip(reference).filter(|(e, r)| e > r).count(),
    }
}

/// Max and summed error over the mantissas that read the entry.
fn line_errors(
    main: &[[u16; 10]; 90],
    (row, second, digit): (usize, bool, usize),
    errors: &[f64],
) -> (f64, f64) {
    let split = line_split(main, row - 10);
    let columns = if second { split..10 } else { 0..split };
    columns
        .map(|col| errors[(row - 10) * 100 + col * 10 + digit])
        .fold((0.0, 0.0), |(max, sum), e| (f64::max(max, e), sum + e))
}

fn assert_within(value: f64, low: f64, high: f64, what: &str) {
    assert!(
        (low..=high).contains(&value),
        "{what}: {value:e} not in [{low:e}, {high:e}]"
    );
}

/// Each entry where the shipped table leaves the published reference holds
/// the derived mean difference, and the published value is the other integer
/// bracketing it.
#[test]
fn test_log_table_small_published() {
    let main = log_table_dec();
    let small = log_table_dec_small();
    let alt = log_table_dec_small_alt();
    for (row, second, digit, published) in PUBLISHED {
        let shipped = if second {
            alt[row - 10][digit]
        } else {
            small[row - 10][digit]
        };
        let derived = derived_entry(&main, row, second, digit);
        assert_eq!(
            shipped, derived,
            "log row {row} second {second} digit {digit}"
        );
        assert_ne!(
            published, derived,
            "log row {row} second {second} digit {digit}"
        );
    }
    let (published_small, published_alt) = published_tables();
    let mut expected: Vec<_> = DEVIATIONS.to_vec();
    expected.extend(
        PUBLISHED
            .iter()
            .map(|&(row, second, digit, _)| (row, second, digit)),
    );
    expected.sort();
    assert_eq!(
        deviations(&main, &published_small, &published_alt),
        expected
    );
}

/// The four-figure lookup error of the shipped, published, all-derived and
/// per-entry selected small tables.
#[test]
fn test_log_lookup_table_variants() {
    let main = log_table_dec();
    let small = log_table_dec_small();
    let alt = log_table_dec_small_alt();
    let (published_small, published_alt) = published_tables();
    let published_errors = lookup_errors(&main, &published_small, &published_alt);

    let published = stats(&published_errors, &published_errors);
    assert_within(published.max, 1.3443e-4, 1.3444e-4, "published max");
    assert_within(published.mean, 3.2936e-5, 3.2937e-5, "published mean");

    let shipped = stats(&lookup_errors(&main, &small, &alt), &published_errors);
    assert_within(shipped.max, 1.1942e-4, 1.1943e-4, "shipped max");
    assert_within(shipped.mean, 3.2955e-5, 3.2956e-5, "shipped mean");
    assert_eq!((shipped.better, shipped.worse), (31, 45));
    assert!(shipped.max < 1.2e-4 && published.max > 1.2e-4);

    let found = deviations(&main, &published_small, &published_alt);
    let derived_entries: Vec<_> = found
        .iter()
        .map(|&(row, second, digit)| (row, second, digit, derived_entry(&main, row, second, digit)))
        .collect();
    let (derived_small, derived_alt) =
        with_entries(&published_small, &published_alt, &derived_entries);
    let derived_errors = lookup_errors(&main, &derived_small, &derived_alt);
    let all_derived = stats(&derived_errors, &published_errors);
    assert_within(all_derived.max, 1.1945e-4, 1.1946e-4, "all derived max");
    assert!(all_derived.mean > published.mean);
    assert_eq!((all_derived.better, all_derived.worse), (61, 88));

    let picks = |rule: &dyn Fn(f64, f64, f64, f64) -> bool| -> Vec<(usize, bool, usize, u8)> {
        derived_entries
            .iter()
            .filter(|&&(row, second, digit, _)| {
                let (published_max, published_sum) =
                    line_errors(&main, (row, second, digit), &published_errors);
                let (derived_max, derived_sum) =
                    line_errors(&main, (row, second, digit), &derived_errors);
                rule(published_max, published_sum, derived_max, derived_sum)
            })
            .cloned()
            .collect()
    };

    // Lowers one of max and summed error on its own line and raises neither.
    let best = picks(&|published_max, published_sum, derived_max, derived_sum| {
        (derived_max <= published_max && derived_sum < published_sum)
            || (derived_max < published_max && derived_sum <= published_sum)
    });
    let keys: Vec<_> = best
        .iter()
        .map(|&(row, second, digit, _)| (row, second, digit))
        .collect();
    assert_eq!(
        keys,
        [
            (10, true, 9),
            (13, true, 4),
            (14, true, 6),
            (16, true, 6),
            (19, true, 4)
        ]
    );
    let (best_small, best_alt) = with_entries(&published_small, &published_alt, &best);
    let best = stats(
        &lookup_errors(&main, &best_small, &best_alt),
        &published_errors,
    );
    assert_eq!(best.max, published.max);
    assert_within(best.mean, 3.289e-5, 3.2891e-5, "per entry best mean");
    assert_eq!((best.better, best.worse), (15, 11));

    // Lowers max error on its own line: exactly the shipped table.
    let lowers_max = picks(&|published_max, _, derived_max, _| derived_max < published_max);
    let keys: Vec<_> = lowers_max
        .iter()
        .map(|&(row, second, digit, _)| (row, second, digit))
        .collect();
    let shipped_keys: Vec<_> = PUBLISHED
        .iter()
        .map(|&(row, second, digit, _)| (row, second, digit))
        .collect();
    assert_eq!(keys, shipped_keys);
    assert_eq!(
        with_entries(&published_small, &published_alt, &lowers_max),
        (small, alt)
    );
}

/// Every small antilog entry is its derived mean difference.
#[test]
fn test_antilog_table_small_derivation() {
    let small = anti_log_table_dec_small();
    for row in 0..100 {
        for digit in 0..10 {
            let derived = round_certified(antilog_mean_difference(row, digit));
            assert_eq!(
                small[row][digit], derived,
                "antilog row .{row:02} digit {digit}"
            );
        }
    }
}

/// Verify the main log table: the base values (without ALT flag) match
/// exactly.
#[test]
fn test_log_table_generation() {
    let generated = generate_log_table();
    let solidity = log_table_dec();
    for row in 0..90 {
        for col in 0..10 {
            let sol = solidity[row][col] & !ALT_TABLE_FLAG;
            assert_eq!(
                generated[row][col], sol,
                "log [{row}][{col}] base: generated={}, solidity={sol}",
                generated[row][col]
            );
        }
    }
}

fn alt_table_flag() -> u16 {
    evm::harness(H::altTableFlagCall {}).unwrap()
}

fn log_table_dec() -> [[u16; 10]; 90] {
    evm::harness(H::logTableDecCall {}).unwrap()
}

fn log_table_dec_small() -> [[u8; 10]; 90] {
    evm::harness(H::logTableDecSmallCall {}).unwrap()
}

fn log_table_dec_small_alt() -> [[u8; 10]; 10] {
    evm::harness(H::logTableDecSmallAltCall {}).unwrap()
}

fn anti_log_table_dec() -> [[u16; 10]; 100] {
    evm::harness(H::antiLogTableDecCall {}).unwrap()
}

fn anti_log_table_dec_small() -> [[u8; 10]; 100] {
    evm::harness(H::antiLogTableDecSmallCall {}).unwrap()
}
