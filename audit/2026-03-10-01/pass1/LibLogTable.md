# Audit Pass 1 (Security) - LibLogTable.sol

**Auditor Agent:** A11
**File:** `src/lib/table/LibLogTable.sol` (742 lines)
**Date:** 2026-03-10

## Evidence of Thorough Reading

### Library
- `LibLogTable` (line 35)

### Constants (file-level)
| Name | Line | Type | Value |
|------|------|------|-------|
| `ALT_TABLE_FLAG` | 7 | `uint16` | `0x8000` |
| `LOG_MANTISSA_IDX_CARDINALITY` | 10 | `uint256` | `9000` |
| `LOG_MANTISSA_LAST_INDEX` | 13 | `uint256` | `8999` |
| `ANTILOG_IDX_CARDINALITY` | 16 | `int256` | `10000` |
| `ANTILOG_IDX_LAST_INDEX` | 19 | `int256` | `9999` |
| `LOG_TABLE_SIZE_BASE` | 25 | `uint256` | `900` |
| `LOG_TABLE_SIZE_BYTES` | 28 | `uint256` | `1800` |
| `LOG_TABLE_DISAMBIGUATOR` | 32 | `bytes32` | `keccak256("LOG_TABLE_DISAMBIGUATOR_1")` |

### Functions
| Function | Line | Visibility | Parameters |
|----------|------|------------|------------|
| `toBytes(uint16[10][90])` | 41 | `internal pure` | log table (main) |
| `toBytes(uint8[10][90])` | 75 | `internal pure` | log table (small) |
| `toBytes(uint8[10][100])` | 109 | `internal pure` | antilog table (small) |
| `toBytes(uint8[10][10])` | 142 | `internal pure` | log table (small alt) |
| `toBytes(uint16[10][100])` | 175 | `internal pure` | antilog table (main) |
| `logTableDec()` | 206 | `internal pure` | returns `uint16[10][90]` |
| `logTableDecSmall()` | 414 | `internal pure` | returns `uint8[10][90]` |
| `logTableDecSmallAlt()` | 512 | `internal pure` | returns `uint8[10][10]` |
| `antiLogTableDec()` | 530 | `internal pure` | returns `uint16[10][100]` |
| `antiLogTableDecSmall()` | 638 | `internal pure` | returns `uint8[10][100]` |

### Types/Errors
- None defined in this file (constants only, no custom types or errors).

## Security Analysis

### Assembly Blocks (5 `toBytes` overloads)

All five `toBytes` functions follow an identical assembly pattern:
1. Allocate memory from free memory pointer for output `bytes`
2. Update free memory pointer
3. Reverse-iterate the 2D array, packing entries from the last element to the first
4. Write the byte length at the start of the output

**Memory safety analysis:**

The `mstore(cursor, value)` writes 32 bytes at each cursor position, but only the trailing 1 or 2 bytes contain the actual value (the rest is zero-padding from the uint16/uint8 value). Because the cursor decrements backward and each new write's trailing bytes land exactly where the previous write's leading zeros were, no data corruption occurs. The final `mstore(cursor, tableSize)` correctly writes the `bytes` length prefix into the first 32-byte slot. All five overloads use the `("memory-safe")` annotation, and the pattern is consistent with Solidity's memory model. The free memory pointer is correctly bumped before the loop begins.

**Loop termination analysis:**

For `uint16[10][90]`: 900 entries x 2 bytes = 1800 bytes. Cursor starts at `encoded + 1800`, decrements by 2 each iteration. After 900 iterations, cursor = `encoded`, and `gt(encoded, encoded)` = false, so the loop terminates. Identical reasoning applies to all overloads, substituting the appropriate entry count and byte width.

### Table Data (Hardcoded Constants)

The five table-returning functions (`logTableDec`, `logTableDecSmall`, `logTableDecSmallAlt`, `antiLogTableDec`, `antiLogTableDecSmall`) return hardcoded 2D arrays. These are pure data -- no arithmetic, no external calls, no assembly.

The `ALT_TABLE_FLAG` (`0x8000`) is OR'd with certain entries in `logTableDec()` (rows 0-9, selected sub-entries in each row). This flag is stripped by the consumer (`lookupLogTableVal` in `LibDecimalFloatImplementation.sol`, line 758: `and(mainTableVal, 0x7FFF)`) and used to select between the regular and alternate small tables. The flag values are always in the first 100 main table entries (indices 0-999), which correctly maps into the 100-byte alt small table bounds.

### External Calls / Data Contract Interaction

`LibLogTable.sol` itself makes NO external calls. It only defines table data and encoding functions. The tables are consumed by `LibDecimalFloatImplementation.sol` via `extcodecopy` to a data contract address. The data contract is deployed deterministically and validated by codehash in `LibDecimalFloatDeploy.sol`. There is no validation at lookup time (in `lookupLogTableVal` or `lookupAntilogTableY1Y2`), but this is a design decision -- the `tablesDataContract` address is a trusted parameter.

### Arithmetic / Overflow

No arithmetic in this file beyond the `ALT_TABLE_FLAG` OR operations in the table data. All values are well within `uint16` range (max table value with flag: `9996 | 0x8000 = 0xA70C`, within uint16 max of 65535). The OR'd values also fit because the maximum base value in the log table is 9996 (< 0x7FFF = 32767).

### Edge Cases and Boundary Lookups

**Index calculations (in consumer, not this file):**

- Log table: index range [0, 8999]. Main table access `(index/10)*2` ranges [0, 1798]. Small table access `(index/100)*10 + (index%10)` ranges [0, 899]. All within bounds of the 1800-byte main table and 900-byte small table.
- Alt small table: triggered only when `ALT_TABLE_FLAG` is set (indices 0-999 region). Access `(index/100)*10 + (index%10)` for index in [0, 999] gives [0, 99]. Within bounds of the 100-byte alt table.
- Antilog table: index range [0, 9999]. Main access `(index/10)*2` ranges [0, 1998]. Small access `(index/100)*10 + (index%10)` ranges [0, 999]. Within bounds of 2000-byte and 1000-byte tables respectively.

## Findings

### A11-1: toBytes Hardcoded Size in Two Overloads (INFORMATIONAL)

**File:** `src/lib/table/LibLogTable.sol`, lines 109-135 and 142-168

**Description:**

Two `toBytes` overloads (`uint8[10][100]` at line 113 and `uint8[10][10]` at line 146) use hardcoded sizes (1000 and 100 respectively) instead of named constants, unlike the other three overloads which use `LOG_TABLE_SIZE_BYTES` and `LOG_TABLE_SIZE_BASE`. Similarly, `toBytes(uint16[10][100])` at line 179 uses hardcoded value 2000.

While these values are correct, the inconsistency could lead to maintenance errors if table dimensions change. The constants `LOG_TABLE_SIZE_BYTES` and `LOG_TABLE_SIZE_BASE` are specifically derived from `LOG_MANTISSA_IDX_CARDINALITY` which relates to the log table dimensions (90 rows), not the antilog dimensions (100 rows) or the alt table dimensions (10 rows), so there is no appropriate constant to reference. This is purely cosmetic.

**Severity:** INFORMATIONAL
**Likelihood:** N/A
**Impact:** None -- values are correct.
**Recommendation:** No action required. Optionally, define named constants for the antilog and alt table sizes for consistency.

### A11-2: No Revert on Undeployed Data Contract (INFORMATIONAL -- design-level note)

**File:** `src/lib/table/LibLogTable.sol` (table definitions), consumed in `src/lib/implementation/LibDecimalFloatImplementation.sol` lines 744-770 and 1227-1254.

**Description:**

The EVM `extcodecopy` instruction reads zeroes from addresses with no deployed code. If the `tablesDataContract` parameter passed to `lookupLogTableVal` or `lookupAntilogTableY1Y2` points to an undeployed address (or an EOA), all table lookups silently return 0. This would cause `log10` and `pow10` to produce incorrect results without reverting.

This is a design-level observation, not a bug in `LibLogTable.sol` itself. The `tablesDataContract` address is a trusted parameter passed by callers. The concrete `DecimalFloat.sol` contract uses a hardcoded `LOG_TABLES_ADDRESS`, and `LibDecimalFloatDeploy.sol` defines a `LOG_TABLES_DATA_CONTRACT_HASH` for verification. However, the lookup functions themselves do not validate the data contract.

**Severity:** INFORMATIONAL
**Likelihood:** Low (requires misconfiguration by integrators)
**Impact:** Incorrect math results for log/pow/sqrt operations, not a loss of funds in isolation.
**Recommendation:** No action required for the library itself. Integrators should ensure the data contract is deployed before calling log/pow/sqrt operations. The existing deterministic deployment pattern and codehash constant provide sufficient guard rails for careful integrators.

### A11-3: Table Data Correctness Relies on CI Comparison (INFORMATIONAL)

**File:** `src/lib/table/LibLogTable.sol`, lines 206-741 (all table-returning functions)

**Description:**

The five hardcoded table functions contain thousands of manually specified numeric values representing log10 and antilog approximations. These values are referenced against a published log table PDF (line 34: `https://icap.org.pk/files/per/students/exam/notices/log-table.pdf`). Correctness is verified by comparing the AOT-compiled bytes (via `toBytes`) against the deployed data contract in CI (as noted in function comments).

A single incorrect value in any table would produce a silently wrong approximation for `log10`, `pow10`, `pow`, or `sqrt`, with no revert. The `ALT_TABLE_FLAG` placement on specific entries (determining which small table variant to use) is also manually specified and an error there would produce silently wrong lookup routing.

**Severity:** INFORMATIONAL
**Likelihood:** Very low (CI comparison catches discrepancies with the deployed contract)
**Impact:** Silent precision errors in log/pow/sqrt operations.
**Recommendation:** The existing CI verification against the deployed data contract is a strong safeguard. Consider additionally verifying a sample of table values against known log10 values in unit tests (e.g., log10(2) = 0.30103, log10(5) = 0.69897, etc.) to confirm the table data is correct at known checkpoints.

## Summary

`LibLogTable.sol` is a data-only library that defines lookup table constants and encoding functions. It contains no external calls, no state mutations, and no complex arithmetic. The assembly in the five `toBytes` functions follows a consistent and correct reverse-packing pattern with proper memory management. The table data is hardcoded and verified in CI.

No LOW or higher severity findings were identified. The three INFORMATIONAL findings are documentation/design observations, not actionable security issues.
