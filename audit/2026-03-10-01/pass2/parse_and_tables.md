# Audit Pass 2 (Test Coverage) - Parser and Log Tables

**Auditor Agents:** A10 (Parser), A11 (Log Tables)
**Date:** 2026-03-10

---

## A10: LibParseDecimalFloat Test Coverage

### Files Read

| File | Lines | Evidence |
|------|-------|----------|
| `src/lib/parse/LibParseDecimalFloat.sol` | 1-197 | 2 functions: `parseDecimalFloatInline`, `parseDecimalFloat`. Imports from `rain.string` (LibParseChar, LibParseDecimal, masks), local errors (MalformedExponentDigits, ParseDecimalPrecisionLoss, MalformedDecimalPoint, ParseDecimalFloatExcessCharacters), and `rain.string/error/ErrParse.sol` (ParseEmptyDecimalString). |
| `test/src/lib/parse/LibParseDecimalFloat.t.sol` | 1-425 | 20 test functions + 2 helpers (`checkParseDecimalFloat`, `checkParseDecimalFloatFail`). Tests cover: fuzz round-trip (integers only), specific literals, leading zeros, decimals, exponents, unrelated trailing data, empty string, non-decimal, e-notation error paths, dot error paths, negative frac, precision loss. |
| `test/src/concrete/DecimalFloat.parse.t.sol` | 1-30 | 1 fuzz test (`testParseDeployed`) that compares library-direct parse against the deployed `DecimalFloat.parse()` contract. |
| `src/error/ErrParse.sol` | 1-19 | 4 errors: MalformedDecimalPoint, MalformedExponentDigits, ParseDecimalPrecisionLoss, ParseDecimalFloatExcessCharacters. |

### Source Function Coverage Map

#### `parseDecimalFloatInline` Code Paths

| # | Code Path | Lines | Error/Return | Tested By |
|---|-----------|-------|-------------|-----------|
| 1 | Empty/non-numeric: no digits after sign skip | 46-47 | `ParseEmptyDecimalString` | `testParseDecimalFloatEmpty`, `testParseDecimalFloatNonDecimal`, `testParseDecimalFloatExponentRevert` (e without number), `testParseLiteralDecimalFloatDotRevert` (`.`), `testParseLiteralDecimalFloatDotRevert2` (`.1`), `testParseLiteralDecimalFloatExponentRevert4-6` (`e1`, `e10`, `e-10`), `testParseLiteralDecimalFloatDotE`, `testParseLiteralDecimalFloatDotE0`, `testParseLiteralDecimalFloatEDot` |
| 2 | Integer part overflow (`unsafeDecimalStringToSignedInt` error) | 52-53 | Propagated error | Covered by fuzz `testParsePacked` implicitly |
| 3 | Decimal point with no trailing digits | 64-65 | `MalformedDecimalPoint` | `testParseLiteralDecimalFloatDotRevert3` (`1.`) |
| 4 | Fractional digits all zeros | 70-74 | fracValue=0, no error | `testParseLiteralDecimalFloatExponents` (`0.0e0`, `0.0e1`) |
| 5 | Fractional digits with trailing zeros stripped | 69-72 | Normal parse | `testParseLiteralDecimalFloatDecimals` (`100.001000`) |
| 6 | Fractional parse overflow (from `unsafeDecimalStringToSignedInt`) | 76-78 | Propagated error | Covered implicitly by fuzz |
| 7 | Negative frac value (sign in fractional part) | 83-84 | `MalformedDecimalPoint` | `testParseLiteralDecimalFloatNegativeFrac` (`0.-1`) |
| 8 | Guard: exponent > 0 (should-not-happen) | 98-100 | `MalformedExponentDigits` | **NOT TESTED** (see A10-6) |
| 9 | signedCoefficient == 0 with nonzero frac | 102-103 | signedCoefficient = fracValue | `testParseLiteralDecimalFloatDecimals` (all `0.xxx` cases) |
| 10 | signedCoefficient != 0: scale > 67 | 108-109 | `ParseDecimalPrecisionLoss` | `testParseLiteralDecimalFloatPrecisionRevert0`, `testParseLiteralDecimalFloatPrecisionRevert1` |
| 11 | signedCoefficient != 0: mul overflow | 117-122 | `ParseDecimalPrecisionLoss` | `testParseLiteralDecimalFloatPrecisionRevert0` (int > int224 * scale) |
| 12 | signedCoefficient != 0: mul truncation | 120-122 | `ParseDecimalPrecisionLoss` | `testParseLiteralDecimalFloatPrecisionRevert1` |
| 13 | signedCoefficient != 0: normal rescale + fracValue | 124 | Normal parse | `testParseLiteralDecimalFloatDecimals` (`1.1`, `10.01`, etc.) |
| 14 | E-notation: no digits after e[sign] | 136-137 | `MalformedExponentDigits` | `testParseDecimalFloatExponentRevert2` (`1e`), `testParseDecimalFloatExponentRevert3` (`1e-`) |
| 15 | E-notation: parse overflow (from `unsafeDecimalStringToSignedInt`) | 143-146 | Propagated error | Covered implicitly by fuzz |
| 16 | E-notation: exponent += eValue | 150 | Normal | `testParseLiteralDecimalFloatExponents` (extensive) |
| 17 | Zero normalization: coefficient == 0 forces exponent = 0 | 153-157 | Normal | `testParseLiteralDecimalFloatExponents` (`0e1`, `0e2`, `0e-1`, `0e-2`, `0.0e0`, `0.0e1`) |

#### `parseDecimalFloat` Code Paths

| # | Code Path | Lines | Error/Return | Tested By |
|---|-----------|-------|-------------|-----------|
| 18 | No error + full string consumed + lossless pack | 178-186 | Success, packed Float | Many tests via `testParsePacked` fuzz |
| 19 | No error + full string consumed + lossy pack | 181-183 | `ParseDecimalPrecisionLoss` | `testParsePacked` fuzz covers this when packing overflows |
| 20 | No error + partial string consumed | 187-189 | `ParseDecimalFloatExcessCharacters` | `testParsePacked` fuzz covers when inline returns partial parse |
| 21 | Inline error propagated | 191-194 | Propagated error selector | `testParsePacked` fuzz |

### Coverage Gaps and Findings

---

#### A10-6: Unreachable guard on positive exponent from fractional part never tested (INFORMATIONAL)

**Location:** `src/lib/parse/LibParseDecimalFloat.sol`, lines 98-100

**Description:**

```solidity
if (exponent > 0) {
    return (MalformedExponentDigits.selector, cursor, 0, 0);
}
```

This guard checks that the exponent computed as `int256(fracStart) - int256(nonZeroCursor)` is not positive. Since `nonZeroCursor >= fracStart` is always true (the nonZeroCursor starts at `cursor >= fracStart` and only decrements), this condition is unreachable in normal execution. The source comment says "Should not be possible but guard against it in case."

No test exercises this code path. Because the guard is genuinely unreachable via the public API, it cannot be tested without mocking internal memory pointers.

**Severity:** INFORMATIONAL
**Impact:** No coverage gap in practice -- the guard is defensive code for a mathematically impossible state.

---

#### A10-7: No dedicated unit test for `ParseDecimalFloatExcessCharacters` from `parseDecimalFloat` wrapper (LOW)

**Location:** `test/src/lib/parse/LibParseDecimalFloat.t.sol`

**Description:**

The `parseDecimalFloat` wrapper (line 187-189 of source) returns `ParseDecimalFloatExcessCharacters` when the inline parser succeeds but does not consume the entire string. While this path is exercised by the fuzz test `testParsePacked` (which has logic for this exact case at line 52-53 of the test), there is no dedicated unit test that calls `parseDecimalFloat` (or `parseDecimalFloatExternal`) with a specific input that triggers this error and asserts the error selector.

By contrast, the inline parser tests in `testParseLiteralDecimalFloatUnrelated` show that partial consumption works correctly at the inline level (e.g., `"1.2.3"` stops at position 3), but these tests call `checkParseDecimalFloat` which tests `parseDecimalFloatInline`, not the wrapper.

A dedicated test such as:
```solidity
function testParseDecimalFloatExcessCharacters() external pure {
    (bytes4 errorSelector, Float float) = this.parseDecimalFloatExternal("1.2.3");
    assertEq(errorSelector, ParseDecimalFloatExcessCharacters.selector);
    assertEq(Float.unwrap(float), bytes32(0));
}
```
would provide explicit, reviewable evidence that this error path works correctly.

**Severity:** LOW
**Impact:** The path is covered by fuzzing, so the risk is minimal. However, fuzz tests may not reliably hit every branch in every run, and the coverage of this specific error path depends on the fuzzer generating strings with valid-prefix + trailing garbage. A deterministic test provides guaranteed coverage.

---

#### A10-8: No test for `ParseDecimalPrecisionLoss` from `packLossy` in `parseDecimalFloat` wrapper (LOW)

**Location:** `test/src/lib/parse/LibParseDecimalFloat.t.sol`

**Description:**

The `parseDecimalFloat` wrapper (lines 181-183 of source) calls `LibDecimalFloat.packLossy(signedCoefficient, exponent)` and returns `ParseDecimalPrecisionLoss` if `lossless` is false. This is a distinct code path from the `ParseDecimalPrecisionLoss` returned by the inline parser (lines 108-109, 121-122), which catches overflows during fractional rescaling.

The wrapper's `packLossy` path is triggered when the inline parser successfully returns a (signedCoefficient, exponent) pair that cannot be losslessly packed into a `Float` (int224 coefficient + int32 exponent). For example, a coefficient exceeding int224 range or an exponent exceeding int32 range, but where the inline parser itself did not detect an error.

The `testParsePacked` fuzz covers this path in its logic (line 62-67), but there is no dedicated unit test with a specific input known to trigger this exact wrapper path. An example input that would trigger it: a string with a valid integer part whose coefficient fits in int256 but not int224, such as `"13479973333575319897333507543509815336818572211270286240551805124605000000000000"` (a 79-digit number).

**Severity:** LOW
**Impact:** Same rationale as A10-7. Fuzz provides probabilistic coverage; a deterministic test would guarantee coverage of this specific wrapper error path.

---

#### A10-9: Fuzz test `testParseLiteralDecimalFloatFuzz` only tests integer inputs, never decimals or e-notation (INFORMATIONAL)

**Location:** `test/src/lib/parse/LibParseDecimalFloat.t.sol`, lines 108-127

**Description:**

The fuzz test `testParseLiteralDecimalFloatFuzz` generates inputs of the form `[-]<leading-zeros><integer>`. It never generates fractional parts (`.xxx`) or e-notation (`eNNN`). This means the fuzz testing only covers the integer-only code path. Fractional and exponent parsing are only covered by the specific/hardcoded tests.

The separate `testParsePacked` fuzz test takes an arbitrary string, which can hit all paths, but the string is not structured -- most random strings will hit `ParseEmptyDecimalString` immediately. The probability of the fuzzer generating a string like `"123.456e7"` is negligible.

**Severity:** INFORMATIONAL
**Impact:** Fractional and e-notation parsing are covered by extensive specific tests, so this is not a gap per se. A structured fuzz test that generates valid decimal+fraction+exponent strings would provide stronger coverage.

---

#### A10-10: `testParsePacked` ExponentOverflow branch has incomplete condition (INFORMATIONAL)

**Location:** `test/src/lib/parse/LibParseDecimalFloat.t.sol`, lines 57-58

**Description:**

The `testParsePacked` fuzz test has a branch to handle `ExponentOverflow`:

```solidity
} else if (exponent != int32(exponent) && exponent > 0 && signedCoefficient == int224(signedCoefficient)) {
    vm.expectRevert(abi.encodeWithSelector(ExponentOverflow.selector, signedCoefficient, exponent));
```

This only handles the case where `exponent > 0` and overflows int32 range. It does not handle the case where `exponent < type(int32).min` (large negative exponent that also doesn't fit int32). The `packLossy` function would handle a large negative exponent differently (it would attempt to normalize, potentially returning `lossless = false`), so this may be intentionally asymmetric. However, the test logic is not obvious and lacks a comment explaining why negative exponent overflow is not handled symmetrically.

**Severity:** INFORMATIONAL
**Impact:** None if the asymmetry is correct. The test would benefit from a comment explaining the logic.

---

## A11: LibLogTable Test Coverage

### Files Read

| File | Lines | Evidence |
|------|-------|----------|
| `src/lib/table/LibLogTable.sol` | 1-742 | 5 `toBytes` overloads, 5 table-returning functions (`logTableDec`, `logTableDecSmall`, `logTableDecSmallAlt`, `antiLogTableDec`, `antiLogTableDecSmall`). Constants: `ALT_TABLE_FLAG`, `LOG_MANTISSA_IDX_CARDINALITY`, `LOG_MANTISSA_LAST_INDEX`, `ANTILOG_IDX_CARDINALITY`, `ANTILOG_IDX_LAST_INDEX`, `LOG_TABLE_SIZE_BASE`, `LOG_TABLE_SIZE_BYTES`, `LOG_TABLE_DISAMBIGUATOR`. |
| `test/src/lib/table/LibLogTable.bytes.t.sol` | 1-33 | 5 test functions, one for each `toBytes` overload. |
| `script/BuildPointers.sol` | 1-47 | Uses all 5 `toBytes` + table functions to generate `LogTables.pointers.sol` via code generation. |

### Source Function Coverage Map

| Function | Tested In | Coverage |
|----------|-----------|----------|
| `toBytes(uint16[10][90])` | `testToBytesLogTableDec` | Called, output logged (no assertions) |
| `toBytes(uint8[10][90])` | `testToBytesLogTableDecSmall` | Called, output logged (no assertions) |
| `toBytes(uint8[10][100])` | `testToBytesAntiLogTableDecSmall` | Called, output logged (no assertions) |
| `toBytes(uint8[10][10])` | `testToBytesLogTableDecSmallAlt` | Called, output logged (no assertions) |
| `toBytes(uint16[10][100])` | `testToBytesAntiLogTableDec` | Called, output logged (no assertions) |
| `logTableDec()` | `testToBytesLogTableDec` | Called as input to `toBytes` |
| `logTableDecSmall()` | `testToBytesLogTableDecSmall` | Called as input to `toBytes` |
| `logTableDecSmallAlt()` | `testToBytesLogTableDecSmallAlt` | Called as input to `toBytes` |
| `antiLogTableDec()` | `testToBytesAntiLogTableDec` | Called as input to `toBytes` |
| `antiLogTableDecSmall()` | `testToBytesAntiLogTableDecSmall` | Called as input to `toBytes` |

### Coverage Gaps and Findings

---

#### A11-4: Log table tests have zero assertions -- they only call and log (LOW)

**Location:** `test/src/lib/table/LibLogTable.bytes.t.sol`, all 5 tests

**Description:**

Every test in `LibLogTable.bytes.t.sol` follows the same pattern:

```solidity
function testToBytesLogTableDec() external pure {
    bytes memory result = LibLogTable.toBytes(LibLogTable.logTableDec());
    console2.logBytes(result);
}
```

The tests call `toBytes` and log the result, but never assert anything about the output. They serve only as smoke tests that confirm the functions don't revert. They do NOT verify:

1. The encoded bytes have the correct length.
2. Any specific byte values are correct.
3. The encoding is consistent with prior known-good output (snapshot testing).
4. Individual table entries round-trip correctly (encode then decode).

The correctness of the table data and encoding is instead verified by CI comparison against the deployed data contract (via `BuildPointers.sol`). However, this CI step is external to the test suite -- running `forge test` alone does not verify table correctness.

**Severity:** LOW
**Impact:** If the table data were accidentally modified (e.g., a typo introduced during a refactor), `forge test` would not catch it. The CI pipeline would, but only if the pointer comparison step runs. A developer running `forge test` locally before committing would get no warning.

**Proposed Test:**

```solidity
function testToBytesLogTableDecLength() external pure {
    bytes memory result = LibLogTable.toBytes(LibLogTable.logTableDec());
    assertEq(result.length, 1800, "Log table dec should be 1800 bytes");
}

function testToBytesLogTableDecSmallLength() external pure {
    bytes memory result = LibLogTable.toBytes(LibLogTable.logTableDecSmall());
    assertEq(result.length, 900, "Log table dec small should be 900 bytes");
}

function testToBytesLogTableDecSmallAltLength() external pure {
    bytes memory result = LibLogTable.toBytes(LibLogTable.logTableDecSmallAlt());
    assertEq(result.length, 100, "Log table dec small alt should be 100 bytes");
}

function testToBytesAntiLogTableDecLength() external pure {
    bytes memory result = LibLogTable.toBytes(LibLogTable.antiLogTableDec());
    assertEq(result.length, 2000, "Antilog table dec should be 2000 bytes");
}

function testToBytesAntiLogTableDecSmallLength() external pure {
    bytes memory result = LibLogTable.toBytes(LibLogTable.antiLogTableDecSmall());
    assertEq(result.length, 1000, "Antilog table dec small should be 1000 bytes");
}
```

---

#### A11-5: No test verifies table data integrity against known log10 reference values (LOW)

**Location:** `test/src/lib/table/LibLogTable.bytes.t.sol`

**Description:**

The five table-returning functions contain thousands of hardcoded numeric values representing log10 approximations. No test verifies any individual table entry against a known mathematical reference. For example:

- `logTableDec()[0][0]` should be `0` (log10(1.00) = 0.0000)
- `logTableDec()[20][0]` should be `3010` (log10(3.0) = 0.4771, but row 20 = mantissa starting at 30, so log10(3.00) mantissa = 4771... actually the row indexing starts at mantissa 10, so row 0 = mantissa 10-19, etc.)
- `antiLogTableDec()[0][0]` should be `1000` (antilog10(0.0000) = 1.000)
- `antiLogTableDec()[99][9]` should be `9977` (last entry, antilog10(0.9999) approx 9.977)

No test spot-checks any of these values. The encoded bytes are logged but never decoded or compared.

**Severity:** LOW
**Impact:** A single-digit typo in the table data would produce silently incorrect results in log10/pow10/sqrt operations. The CI pointer comparison catches discrepancies with the deployed contract, but does not verify the deployed contract is correct in the first place.

**Proposed Test:**

```solidity
function testLogTableDecKnownValues() external pure {
    uint16[10][90] memory table = LibLogTable.logTableDec();
    // First entry: log10(1.00) mantissa = 0
    assertEq(table[0][0], 0);
    // log10(2.00) = 0.3010, row 10 (mantissa 20), col 0
    assertEq(table[10][0], 3010);
    // Last entry: row 89, col 9
    assertEq(table[89][9], 9996);
}

function testAntiLogTableDecKnownValues() external pure {
    uint16[10][100] memory table = LibLogTable.antiLogTableDec();
    // First entry: antilog10(0.0000) = 1.000
    assertEq(table[0][0], 1000);
    // Last entry: antilog10(0.9999) approx 9.977
    assertEq(table[99][9], 9977);
}
```

---

#### A11-6: No test for `toBytes` encoding correctness (round-trip or spot-check) (LOW)

**Location:** `test/src/lib/table/LibLogTable.bytes.t.sol`

**Description:**

The five `toBytes` functions use inline assembly to pack 2D arrays into flat byte arrays. No test verifies that the encoding is correct by either:

1. Decoding the result and comparing against the original array (round-trip).
2. Spot-checking specific byte positions in the output.

The assembly in these functions is non-trivial (reverse iteration, mixed 1-byte and 2-byte packing, nested array pointer arithmetic). A bug in the assembly would silently produce incorrect encoded bytes that would then be deployed as the data contract, causing incorrect log/antilog lookups.

**Severity:** LOW
**Impact:** If the `toBytes` assembly had a bug (e.g., off-by-one in loop bounds, wrong byte width), the deployed data contract would contain incorrect data. The current tests would not catch this because they only check that the function doesn't revert.

**Proposed Test:**

```solidity
function testToBytesLogTableDecSpotCheck() external pure {
    bytes memory result = LibLogTable.toBytes(LibLogTable.logTableDec());
    // First entry (uint16): table[0][0] = 0 -> bytes 0-1 should be 0x0000
    assertEq(uint8(result[0]), 0);
    assertEq(uint8(result[1]), 0);
    // Second entry: table[0][1] = 43 = 0x002B -> bytes 2-3
    assertEq(uint8(result[2]), 0);
    assertEq(uint8(result[3]), 43);
    // Last entry: table[89][9] = 9996 = 0x270C -> bytes 1798-1799
    assertEq(uint8(result[1798]), 0x27);
    assertEq(uint8(result[1799]), 0x0C);
}
```

---

#### A11-7: No test for `ALT_TABLE_FLAG` presence and placement in `logTableDec` (INFORMATIONAL)

**Location:** `src/lib/table/LibLogTable.sol`, lines 207-408

**Description:**

The `logTableDec()` function has `ALT_TABLE_FLAG` (0x8000) OR'd onto specific entries in rows 0-9. These flagged entries route lookups to the alternate small table in the consumer code (`LibDecimalFloatImplementation.sol`). No test verifies:

1. Which entries have the flag set.
2. That the flag is only present in rows 0-9 (the first 100 entries).
3. That the flag is correctly stripped by the consumer (tested elsewhere in log/pow tests, but not isolated).

**Severity:** INFORMATIONAL
**Impact:** The flag placement is verified indirectly through the end-to-end log/pow tests and the CI pointer comparison. An isolated test would provide better visibility into this specific aspect.

---

#### A11-8: No edge-case boundary tests for table lookups at index 0 and last index (INFORMATIONAL)

**Location:** `test/src/lib/table/LibLogTable.bytes.t.sol`

**Description:**

The consumer code in `LibDecimalFloatImplementation.sol` accesses table entries at indices 0 through `LOG_MANTISSA_LAST_INDEX` (8999) for log tables and 0 through `ANTILOG_IDX_LAST_INDEX` (9999) for antilog tables. No test in the table test file verifies that:

1. The encoded bytes at index 0 are correct (first-entry correctness).
2. The encoded bytes at the last index are correct (last-entry correctness, no off-by-one in the encoding loop).

These boundary entries are the most likely to be wrong if there is an off-by-one in the assembly loop.

**Severity:** INFORMATIONAL
**Impact:** End-to-end log/pow tests provide indirect coverage. The boundary entries are correct (verified by reading the source data), but there is no isolated test that catches an encoding regression at the boundaries.

---

## Summary

### A10 (Parser) Findings

| ID | Severity | Title |
|----|----------|-------|
| A10-6 | INFORMATIONAL | Unreachable guard on positive exponent from fractional part never tested |
| A10-7 | LOW | No dedicated unit test for `ParseDecimalFloatExcessCharacters` from wrapper |
| A10-8 | LOW | No dedicated unit test for `ParseDecimalPrecisionLoss` from `packLossy` in wrapper |
| A10-9 | INFORMATIONAL | Fuzz test only generates integer inputs, never decimals or e-notation |
| A10-10 | INFORMATIONAL | `testParsePacked` ExponentOverflow branch has incomplete condition |

### A11 (Log Tables) Findings

| ID | Severity | Title |
|----|----------|-------|
| A11-4 | LOW | Log table tests have zero assertions -- they only call and log |
| A11-5 | LOW | No test verifies table data integrity against known log10 reference values |
| A11-6 | LOW | No test for `toBytes` encoding correctness (round-trip or spot-check) |
| A11-7 | INFORMATIONAL | No test for `ALT_TABLE_FLAG` presence and placement |
| A11-8 | INFORMATIONAL | No edge-case boundary tests for table lookups at index 0 and last index |

### Overall Assessment

**Parser (A10):** The inline parser `parseDecimalFloatInline` has good deterministic test coverage across its error paths, with specific tests for empty strings, non-numeric input, malformed decimals, malformed exponents, negative fractions, and precision loss. The fuzz test `testParsePacked` provides broad coverage of the wrapper function. The main gaps are the absence of dedicated unit tests for the wrapper's own error returns (`ParseDecimalFloatExcessCharacters` and `ParseDecimalPrecisionLoss` from `packLossy`), which are currently only covered probabilistically by fuzzing.

**Log Tables (A11):** Test coverage is essentially smoke-test level. All five `toBytes` functions are called but their outputs are never verified. Table data integrity relies entirely on the external CI pointer comparison step. Running `forge test` locally provides no assurance that the table data or encoding is correct. This is the most significant coverage gap found in this pass.
