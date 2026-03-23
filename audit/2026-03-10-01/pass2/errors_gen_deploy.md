# Audit Pass 2 -- Test Coverage: Error Definitions, Generated Constants, Deploy Library

**Agents:** A02, A03, A04, A05, A07

---

## A02: `src/error/ErrDecimalFloat.sol`

**Errors defined (13 total):**

| Error | Line | Tested via `vm.expectRevert`? | Test File(s) |
|---|---|---|---|
| `CoefficientOverflow` | 8 | NO -- imported in parse test but never asserted | (imported only in `LibParseDecimalFloat.t.sol`) |
| `ExponentOverflow` | 11 | YES | `LibDecimalFloat.pack.t.sol`, `LibDecimalFloat.pow10.t.sol`, `LibParseDecimalFloat.t.sol`, `LibDecimalFloat.decimal.t.sol`, `LibDecimalFloatImplementation.add.t.sol` |
| `NegativeFixedDecimalConversion` | 15 | YES | `LibDecimalFloat.decimal.t.sol` |
| `Log10Zero` | 18 | NO | (none) |
| `Log10Negative` | 21 | NO | (none) |
| `LossyConversionToFloat` | 25 | YES | `LibDecimalFloat.decimalLossless.t.sol` |
| `LossyConversionFromFloat` | 29 | YES | `LibDecimalFloat.decimalLossless.t.sol` |
| `ZeroNegativePower` | 32 | YES | `LibDecimalFloat.pow.t.sol` |
| `MulDivOverflow` | 35 | NO | (none) |
| `MaximizeOverflow` | 38 | YES | `LibDecimalFloatImplementation.div.t.sol` |
| `DivisionByZero` | 43 | YES | `LibDecimalFloatImplementation.div.t.sol`, `LibDecimalFloatImplementation.inv.t.sol` |
| `PowNegativeBase` | 46 | YES | `LibDecimalFloat.pow.t.sol`, `LibDecimalFloat.sqrt.t.sol` |
| `WriteError` | 49 | NO -- imported in deploy lib but never used in any `revert` statement | (dead code) |

**Evidence of reading:** All 13 error definitions at lines 7-49 were read. Each error name was grepped across the entire `test/` directory for both `files_with_matches` and then for `.selector` / `(` patterns to distinguish import-only from actual assertion usage.

---

## A03: `src/error/ErrFormat.sol`

**Errors defined (1 total):**

| Error | Line | Tested via `vm.expectRevert`? | Test File(s) |
|---|---|---|---|
| `UnformatableExponent` | 7 | NO | (none) |

The error is thrown in `LibFormatDecimalFloat.sol` at line 85 when `exponent < -76`. The format test file (`LibFormatDecimalFloat.toDecimalString.t.sol`) contains no `vm.expectRevert` calls at all and never exercises exponents below -76 in a way that would trigger this branch.

**Evidence of reading:** The single error definition at line 7 was read. Grepped `test/` for `UnformatableExponent` -- zero matches. Grepped format test file for any `revert` or `expectRevert` -- zero matches.

---

## A04: `src/error/ErrParse.sol`

**Errors defined (4 total):**

| Error | Line | Tested via assertion? | Test File(s) |
|---|---|---|---|
| `MalformedDecimalPoint` | 7 | YES (selector comparison) | `LibParseDecimalFloat.t.sol` |
| `MalformedExponentDigits` | 11 | YES (selector comparison) | `LibParseDecimalFloat.t.sol` |
| `ParseDecimalPrecisionLoss` | 16 | YES (selector comparison) | `LibParseDecimalFloat.t.sol` |
| `ParseDecimalFloatExcessCharacters` | 19 | YES (selector comparison) | `LibParseDecimalFloat.t.sol` |

All four parse errors are tested via `checkParseDecimalFloatFail` which asserts the error selector matches. Coverage is adequate.

**Evidence of reading:** All 4 error definitions at lines 6-19 were read. Each error was found in `test/src/lib/parse/LibParseDecimalFloat.t.sol` with explicit selector assertions.

---

## A05: `src/generated/LogTables.pointers.sol`

**Constants defined (6 total):**

| Constant | Line | Description |
|---|---|---|
| `BYTECODE_HASH` | 13 | Placeholder `0x0...0` -- appears to be unused/stale |
| `LOG_TABLES` | 16-17 | Main log lookup table (hex data) |
| `LOG_TABLES_SMALL` | 19-21 | Small log table |
| `LOG_TABLES_SMALL_ALT` | 23-25 | Small alt log table |
| `ANTI_LOG_TABLES` | 27-29 | Anti-log lookup table |
| `ANTI_LOG_TABLES_SMALL` | 31-33 | Small anti-log table |

**Test coverage:**

- `BYTECODE_HASH` is set to all zeros and is not referenced in any test or source file outside this generated file. It appears to be a stale placeholder from the code generation template.
- The five table constants (`LOG_TABLES`, `LOG_TABLES_SMALL`, `LOG_TABLES_SMALL_ALT`, `ANTI_LOG_TABLES`, `ANTI_LOG_TABLES_SMALL`) are consumed by `LibDecimalFloatDeploy.combinedTables()`, which concatenates them all together.
- `combinedTables()` is called in `test/abstract/LogTest.sol` (line 18), which deploys the tables to an in-memory EVM and asserts the deployed codehash matches `LOG_TABLES_DATA_CONTRACT_HASH`. This provides an integrity check that the combined table data matches the expected hash.
- `combinedTables()` is also called in `test/src/lib/deploy/LibDecimalFloatDeploy.t.sol` for deployment address and codehash validation.
- The `LOG_TABLE_DISAMBIGUATOR` (from `LibLogTable.sol`) is appended to the combined tables but has no standalone test of its value.
- There are no tests that validate individual table entries against reference values or known mathematical identities (e.g., verifying that `log10(1000) = 3` is correctly encoded in the table data).
- The tables are indirectly validated via the log10/pow10 functional tests that perform lookups against the deployed data contract and verify mathematical results.

**Evidence of reading:** All 6 constants were read. `BYTECODE_HASH` was grepped across the codebase -- found only in this file, `lib/rain.sol.codegen/`, and a pass1 audit file. The five table constants were traced through `combinedTables()` into `LogTest.sol` and `LibDecimalFloatDeploy.t.sol`.

---

## A07: `src/lib/deploy/LibDecimalFloatDeploy.sol`

**Source elements (4 constants + 1 function):**

| Element | Line | Description |
|---|---|---|
| `ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS` | 23 | Deterministic address for log tables |
| `LOG_TABLES_DATA_CONTRACT_HASH` | 27 | Expected codehash for log tables |
| `ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS` | 32 | Deterministic address for DecimalFloat |
| `DECIMAL_FLOAT_CONTRACT_HASH` | 36 | Expected codehash for DecimalFloat |
| `combinedTables()` | 42-51 | Concatenates all table constants |

**Test files examined:**

### `test/src/lib/deploy/LibDecimalFloatDeploy.t.sol`

| Test | What it covers |
|---|---|
| `testDeployAddress` | Deploys `DecimalFloat` via Zoltu proxy on forked Ethereum; asserts address == `ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS` and codehash == `DECIMAL_FLOAT_CONTRACT_HASH` |
| `testExpectedCodeHashDecimalFloat` | Deploys `DecimalFloat` locally via `new`; asserts codehash == `DECIMAL_FLOAT_CONTRACT_HASH` |
| `testDeployAddressLogTables` | Deploys combined tables via Zoltu proxy on forked Ethereum; asserts address == `ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS` and codehash == `LOG_TABLES_DATA_CONTRACT_HASH` |
| `testExpectedCodeHashLogTables` | Deploys combined tables locally via `create`; asserts codehash == `LOG_TABLES_DATA_CONTRACT_HASH` and non-empty code |

### `test/src/lib/deploy/LibDecimalFloatDeployProd.t.sol`

| Test | What it covers |
|---|---|
| `testProdDeploymentArbitrum` | Checks both contracts exist on Arbitrum with correct codehashes |
| `testProdDeploymentBase` | Checks both contracts exist on Base with correct codehashes |
| `testProdDeploymentBaseSepolia` | Checks both contracts exist on Base Sepolia with correct codehashes |
| `testProdDeploymentFlare` | Checks both contracts exist on Flare with correct codehashes |
| `testProdDeploymentPolygon` | Checks both contracts exist on Polygon with correct codehashes |

All 4 constants and the `combinedTables()` function are covered. The prod test provides cross-chain verification. The `combinedTables()` function is additionally exercised in `test/abstract/LogTest.sol` (used by all log10/pow10 tests).

**Evidence of reading:** Both test files read in full (47 and 53 lines respectively). All constants traced to test assertions. `combinedTables()` traced to both deploy tests and `LogTest.sol`.

---

## Findings

### A02-1 [LOW] `Log10Zero` error has no direct test

**Location:** `src/error/ErrDecimalFloat.sol:18`, thrown at `src/lib/implementation/LibDecimalFloatImplementation.sol:795`

The `Log10Zero()` error, thrown when attempting `log10(0)`, is never explicitly tested. The log10 test in `LibDecimalFloatImplementation.log10.t.sol` only tests positive values. The fuzz test in `LibDecimalFloat.log10.t.sol` uses a generic `try/catch` that would catch any revert but does not assert the specific error selector. No test explicitly calls `log10(0, 0)` and asserts `Log10Zero()` is thrown.

This is a meaningful gap because `log10(0)` is a mathematically undefined operation that users could easily attempt (e.g., `log10(0)` in a Rainlang expression). Confirming the correct error is thrown is important for debugging.

### A02-2 [LOW] `Log10Negative` error has no direct test

**Location:** `src/error/ErrDecimalFloat.sol:21`, thrown at `src/lib/implementation/LibDecimalFloatImplementation.sol:797`

The `Log10Negative` error, thrown when attempting `log10` of a negative number, is never explicitly tested. Same situation as A02-1: the fuzz test catches reverts generically but never asserts this specific error. No test explicitly calls `log10(-1, 0)` and asserts `Log10Negative(-1, 0)`.

### A02-3 [LOW] `MulDivOverflow` error has no test

**Location:** `src/error/ErrDecimalFloat.sol:35`, thrown at `src/lib/implementation/LibDecimalFloatImplementation.sol:491`

The `MulDivOverflow` error, thrown when a 512-bit intermediate product exceeds the denominator in the internal `mulDiv` function, has no test anywhere. No test file references `MulDivOverflow.selector` or constructs inputs that trigger this specific overflow path. This is a critical internal guard in the multiply/divide pipeline.

### A02-4 [LOW] `CoefficientOverflow` error has no direct test

**Location:** `src/error/ErrDecimalFloat.sol:8`, thrown at `src/lib/LibDecimalFloat.sol:361`

The `CoefficientOverflow` error is imported in the parse test file but is never actually asserted via `vm.expectRevert` or selector comparison. No test explicitly constructs a coefficient too large for `int224` and verifies this error is thrown by `packLossless`. The parse test's `try/catch` may catch it generically during fuzz runs, but there is no targeted test.

### A02-5 [INFO] `WriteError` is dead code

**Location:** `src/error/ErrDecimalFloat.sol:49`, imported at `src/lib/deploy/LibDecimalFloatDeploy.sol:17`

The `WriteError` error is defined and imported but never used in any `revert` statement anywhere in the codebase. The `LibDecimalFloatDeploy.sol` file contains zero `revert` statements. This error appears to be dead code from a previous version of the deploy library that may have included a `create`-based deployment with failure checks.

### A03-1 [LOW] `UnformatableExponent` error has no test

**Location:** `src/error/ErrFormat.sol:7`, thrown at `src/lib/format/LibFormatDecimalFloat.sol:85`

The `UnformatableExponent` error is thrown when attempting to format a Float with `exponent < -76` in non-scientific mode. No test exercises this path. The format test file (`LibFormatDecimalFloat.toDecimalString.t.sol`) contains no `vm.expectRevert` calls and never constructs an input that would trigger this error. A test should format a value like `packLossless(1, -77)` in non-scientific mode and assert the revert.

### A05-1 [INFO] `BYTECODE_HASH` constant is a zero placeholder

**Location:** `src/generated/LogTables.pointers.sol:13`

The `BYTECODE_HASH` constant is set to `0x000...000` and is not referenced anywhere in the codebase outside this generated file and the codegen library. It appears to be a vestigial template output. It is not used by any production or test code.

### A05-2 [INFO] No standalone validation of individual table entries

**Location:** `src/generated/LogTables.pointers.sol:16-33`

While the combined table data is validated via codehash in deployment tests, there are no tests that verify individual lookup table entries against known mathematical values. The functional log10/pow10 tests provide indirect coverage by checking computed results, which is likely sufficient, but a corruption of a single table entry could potentially be masked by the linear interpolation between entries.
