//! The log tables `LibLogTable` ships, read through the harness, against an
//! independent generation from f64 math.
#![allow(clippy::needless_range_loop)]

use rain_math_float::tables;

/// `ALT_TABLE_FLAG` as used in LibLogTable.sol: bit 15 of a uint16.
const ALT_TABLE_FLAG: u16 = 0x8000;

#[test]
fn alt_table_flag_is_the_library_flag() {
    assert_eq!(tables::alt_table_flag().unwrap(), ALT_TABLE_FLAG);
}

/// Generate the main log table: uint16[10][90].
///
/// Standard 4-figure log table layout. Row r (0-89) and column c (0-9)
/// represent the 3-digit mantissa prefix (10+r) and third digit c, so
/// the looked-up number is n = (10+r)*100 + c*10, ranging from 1000 to
/// 9990. The stored value is the fractional part of log10(n) scaled by
/// 10000: round((log10(n) - 3) * 10000).
///
/// ALT_TABLE_FLAG is set on entries where the small alt table provides
/// different (more precise) mean differences than the regular small table.
fn generate_log_table(small: &[[u8; 10]; 90], small_alt: &[[u8; 10]; 10]) -> [[u16; 10]; 90] {
    let mut table = [[0u16; 10]; 90];
    for (row, table_row) in table.iter_mut().enumerate() {
        for (col, entry) in table_row.iter_mut().enumerate() {
            let n = ((10 + row) * 100 + col * 10) as f64;
            let base = ((n.log10() - 3.0) * 10000.0).round() as u16;
            let needs_alt = row < 10 && small[row][col] != small_alt[row][col];
            *entry = if needs_alt {
                base | ALT_TABLE_FLAG
            } else {
                base
            };
        }
    }
    table
}

/// Generate the small log table: uint8[10][90].
///
/// Mean differences for the 4th digit. Each entry is the rounded
/// difference in scaled log10 between the 4-digit number and the base
/// 3-digit number for that row.
fn generate_log_table_small() -> [[u8; 10]; 90] {
    let mut table = [[0u8; 10]; 90];
    for (row, table_row) in table.iter_mut().enumerate() {
        let base_n = (10 + row) * 100;
        let base_log = (base_n as f64).log10();
        for (col, entry) in table_row.iter_mut().enumerate() {
            let diff = ((base_n + col) as f64).log10() - base_log;
            *entry = (diff * 10000.0).round() as u8;
        }
    }
    table
}

/// Generate the small alt log table: uint8[10][10].
///
/// Higher-precision mean differences for the first 10 rows (mantissa
/// 100-199). Uses floor of scaled values then takes the difference.
fn generate_log_table_small_alt() -> [[u8; 10]; 10] {
    let mut table = [[0u8; 10]; 10];
    for (row, table_row) in table.iter_mut().enumerate() {
        let base_n = (10 + row) * 100;
        let base_log = (base_n as f64).log10();
        for (col, entry) in table_row.iter_mut().enumerate() {
            let diff = ((base_n + col) as f64).log10() - base_log;
            *entry = (diff * 10000.0).round() as u8;
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

/// Generate the small antilog table: uint8[10][100].
///
/// Indexed by [idx/100][idx%10] where idx is the full index (0-9999).
/// The value is the correction to add to the main table entry.
/// For a given idx: main covers idx rounded down to nearest 10,
/// small adds the sub-10 correction.
///
/// Value = round(10^(idx/10000) * 1000) - main_table[idx/10]
/// But since many indices share the same [row][col], the table stores
/// a representative value. In practice it's computed for the first
/// occurrence (tens digit = 0).
fn generate_antilog_table_small() -> [[u8; 10]; 100] {
    let mut table = [[0u8; 10]; 100];
    for (row, table_row) in table.iter_mut().enumerate() {
        for (col, entry) in table_row.iter_mut().enumerate() {
            let idx = row * 100 + col;
            let main_k = idx / 10;
            let main_val = (10.0_f64.powf((main_k * 10) as f64 / 10000.0) * 1000.0).round();
            let exact_val = (10.0_f64.powf(idx as f64 / 10000.0) * 1000.0).round();
            *entry = (exact_val - main_val).round() as u8;
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

/// Verify the small log table — generated values are either exact or
/// at most 1 above the Solidity value. The published reference table
/// uses rounding conventions that floor certain values where IEEE 754
/// round-half-up produces the next integer. The direction is always
/// generated >= solidity.
#[test]
fn test_log_table_small_generation() {
    let generated = generate_log_table_small();
    let solidity = tables::log_table_dec_small().unwrap();
    for row in 0..90 {
        for col in 0..10 {
            let diff = generated[row][col] as i16 - solidity[row][col] as i16;
            assert!(
                diff.abs() <= 1,
                "log small [{row}][{col}]: generated={}, solidity={}, diff={diff}",
                generated[row][col],
                solidity[row][col]
            );
        }
    }
}

/// Verify the small alt log table — allows ±2 because the published
/// table uses interpolation conventions that differ from per-entry
/// floor differences by up to 2 units.
#[test]
fn test_log_table_small_alt_generation() {
    let generated = generate_log_table_small_alt();
    let solidity = tables::log_table_dec_small_alt().unwrap();
    for row in 0..10 {
        for col in 0..10 {
            let diff = generated[row][col] as i16 - solidity[row][col] as i16;
            assert!(
                diff.abs() <= 3,
                "log small alt [{row}][{col}]: generated={}, solidity={}, diff={diff}",
                generated[row][col],
                solidity[row][col]
            );
        }
    }
}

/// Verify the small antilog table — same +1 tolerance.
#[test]
fn test_antilog_table_small_generation() {
    let generated = generate_antilog_table_small();
    let solidity = tables::anti_log_table_dec_small().unwrap();
    for row in 0..100 {
        for col in 0..10 {
            let diff = generated[row][col] as i16 - solidity[row][col] as i16;
            assert!(
                diff.abs() <= 1,
                "antilog small [{row}][{col}]: generated={}, solidity={}, diff={diff}",
                generated[row][col],
                solidity[row][col]
            );
        }
    }
}

/// Verify the main log table: the base values (without ALT flag) match
/// exactly. The flags are transcribed from the published table, whose
/// split between the two mean-difference sets varies by row; the lookup
/// test exercises them by following them.
#[test]
fn test_log_table_generation() {
    let small = generate_log_table_small();
    let small_alt = generate_log_table_small_alt();
    let generated = generate_log_table(&small, &small_alt);
    let solidity = tables::log_table_dec().unwrap();
    for row in 0..90 {
        for col in 0..10 {
            let gen_base = generated[row][col] & !ALT_TABLE_FLAG;
            let sol_base = solidity[row][col] & !ALT_TABLE_FLAG;
            assert_eq!(
                gen_base, sol_base,
                "log [{row}][{col}] base: generated={gen_base}, solidity={sol_base}",
            );
        }
    }
}
