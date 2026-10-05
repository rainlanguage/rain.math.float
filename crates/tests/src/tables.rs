//! The log tables `LibLogTable` ships, read through the harness, against
//! derivations of the published four-figure tables.
#![allow(clippy::needless_range_loop)]

use rain_math_float::tables;

/// `ALT_TABLE_FLAG` as used in LibLogTable.sol: bit 15 of a uint16.
const ALT_TABLE_FLAG: u16 = 0x8000;

#[test]
fn alt_table_flag_is_the_library_flag() {
    assert_eq!(tables::alt_table_flag().unwrap(), ALT_TABLE_FLAG);
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
    let table = tables::log_table_dec().unwrap();
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
    let table = tables::anti_log_table_dec().unwrap();
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
    let main = tables::log_table_dec().unwrap();
    let small = tables::log_table_dec_small().unwrap();
    let small_alt = tables::log_table_dec_small_alt().unwrap();
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
    let main = tables::anti_log_table_dec().unwrap();
    let small = tables::anti_log_table_dec_small().unwrap();
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
    let solidity = tables::anti_log_table_dec().unwrap();
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
    assert!(margin > 1e-6, "{value} is too close to a half to round from f64");
    value.round() as u8
}

/// Entries where the published reference holds the other integer that
/// brackets the derived mean difference, as (log row, second line, digit).
/// The reference is not one formula: no single mean difference reproduces
/// log row 12's first line or row 13's second line.
const DEVIATIONS: [(usize, bool, usize); 28] = [
    (10, false, 2),
    (10, false, 6),
    (10, true, 9),
    (11, true, 5),
    (12, false, 1),
    (13, true, 2),
    (13, true, 3),
    (13, true, 4),
    (13, true, 9),
    (14, true, 6),
    (14, true, 7),
    (14, true, 8),
    (14, true, 9),
    (16, false, 5),
    (16, false, 8),
    (16, true, 6),
    (17, true, 8),
    (18, false, 4),
    (18, false, 7),
    (18, true, 5),
    (18, true, 8),
    (19, false, 2),
    (19, false, 6),
    (19, true, 3),
    (19, true, 4),
    (19, true, 8),
    (19, true, 9),
    (74, false, 6),
];

/// Every small log entry is its derived mean difference, or is listed in
/// DEVIATIONS and is the other integer bracketing it.
#[test]
fn test_log_table_small_derivation() {
    let main = tables::log_table_dec().unwrap();
    let small = tables::log_table_dec_small().unwrap();
    let alt = tables::log_table_dec_small_alt().unwrap();
    let mut deviations = Vec::new();
    for row in 0..90 {
        let split = line_split(&main, row);
        assert_eq!(split < 10, row < 10, "log row {}: line split {split}", 10 + row);
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
    assert_eq!(deviations, DEVIATIONS);
}

/// Every small antilog entry is its derived mean difference.
#[test]
fn test_antilog_table_small_derivation() {
    let small = tables::anti_log_table_dec_small().unwrap();
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
    let solidity = tables::log_table_dec().unwrap();
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
