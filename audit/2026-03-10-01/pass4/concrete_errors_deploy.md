# Pass 4 -- Code Quality: Concrete, Errors, Deploy, Generated, Scripts

**Auditor agents:** A01, A02, A03, A04, A05, A07, A12, A13
**Date:** 2026-03-10
**Scope:**
- `src/concrete/DecimalFloat.sol`
- `src/error/ErrDecimalFloat.sol`
- `src/error/ErrFormat.sol`
- `src/error/ErrParse.sol`
- `src/generated/LogTables.pointers.sol`
- `src/lib/deploy/LibDecimalFloatDeploy.sol`
- `script/BuildPointers.sol`
- `script/Deploy.sol`

---

## Findings

### A07-01 | LOW | Unused imports in `LibDecimalFloatDeploy.sol`

**File:** `src/lib/deploy/LibDecimalFloatDeploy.sol` lines 12-15, 17

Five imports are not referenced anywhere in the library's code:

1. `LibDataContract` (line 12)
2. `DataContractMemoryContainer` (line 12)
3. `LibBytes` (line 13)
4. `LibMemCpy` (line 14)
5. `Pointer` (line 14)
6. `WriteError` (line 17)
7. `DecimalFloat` (line 15) -- the contract type itself is never used in any function or constant expression; only its *name* appears in NatSpec comments.

The library only defines constants and `combinedTables()`, which uses only the table data constants and `LOG_TABLE_DISAMBIGUATOR`. These seven unused imports bloat the compilation unit and may confuse readers about the library's actual dependencies.

**Recommendation:** Remove lines 12-15 and 17 entirely. Remove line 15 (`DecimalFloat` import) as well if the contract type is not needed for type-level references.

---

### A01-01 | LOW | `require` with string literal instead of custom error

**File:** `src/concrete/DecimalFloat.sol` line 79

```solidity
require(scientificMin.lt(scientificMax), "scientificMin must be less than scientificMax");
```

Every other error path in the codebase uses custom errors (defined in `src/error/`). This single `require` with a string literal is inconsistent and costs more gas than a custom error (each character of the string is stored in the revert data).

**Recommendation:** Define a custom error (e.g., `error ScientificMinNotLessThanMax(Float min, Float max);`) in the error directory and use `if (!scientificMin.lt(scientificMax)) revert ScientificMinNotLessThanMax(scientificMin, scientificMax);` instead.

---

### A01-02 | INFO | Missing blank line between `zero()` and `e()` NatSpec blocks

**File:** `src/concrete/DecimalFloat.sol` lines 50-54

```solidity
    function zero() external pure returns (Float) {
        return LibDecimalFloat.FLOAT_ZERO;
    }
    /// Exposes `LibDecimalFloat.FLOAT_E` for offchain use.
    /// @return The constant value of Euler's number as a Float.

    function e() external pure returns (Float) {
```

Every other function pair in this contract has a blank line separating the closing brace from the next NatSpec block. The `zero()`/`e()` pair is missing this blank line, and instead has a blank line *between* the NatSpec and the function signature. Both are style inconsistencies.

**Recommendation:** Add a blank line after the closing brace of `zero()` (before the `///` of `e()`), and remove the blank line between the `@return` tag and the `function e()` signature.

---

### A01-03 | INFO | Bare `"src/"` import paths in test files (74 files, 123 occurrences)

**Scope:** `test/` directory

All 74 test files use bare `"src/"` import paths (e.g., `import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";`). These paths rely on Foundry's `src = 'src'` auto-detection, which resolves `"src/"` to the project root's `src/` directory. When this repo is consumed as a git submodule, a parent project's Foundry config will resolve `"src/"` to the *parent's* `src/` directory, breaking all test imports.

This does not affect production (`src/`) files, which correctly use relative paths. It also does not affect scripts, which use `"../src/"` relative paths.

While tests are not typically compiled by downstream consumers, the inconsistency with the relative-path convention in `src/` and `script/` is worth noting.

**Recommendation:** Convert test imports to relative paths (e.g., `"../../src/lib/LibDecimalFloat.sol"`) or add a Foundry remapping to make them submodule-safe.

---

### A05-01 | INFO | `BYTECODE_HASH` constant is always zero and never referenced

**File:** `src/generated/LogTables.pointers.sol` line 13

```solidity
bytes32 constant BYTECODE_HASH = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);
```

This constant is emitted by the codegen framework (`rain.sol.codegen`) as part of its `buildFileForContract` template. It is always zero because `BuildPointers.sol` passes `address(0)` (no deployed instance to hash). The constant is never imported or used anywhere in the project.

This is a consequence of the codegen library's generic template and is not a bug, but it is dead code that could confuse readers.

**Recommendation:** No action needed -- this is generated code controlled by the `rain.sol.codegen` dependency. If the codegen library adds opt-out support in the future, consider suppressing the constant.

---

### A01-04 | INFO | Pragma version inconsistency between concrete/script and library files

**Observation:**
- `src/concrete/DecimalFloat.sol`: `pragma solidity =0.8.25;` (exact)
- `script/BuildPointers.sol`: `pragma solidity =0.8.25;` (exact)
- `script/Deploy.sol`: `pragma solidity =0.8.25;` (exact)
- All library/error/generated files: `pragma solidity ^0.8.25;` (range)

This is intentional and correct: concrete contracts and scripts pin the exact compiler version, while libraries use `^` to allow consumers to compile with later patch versions. No action needed.

---

### A02-01 | INFO | `ErrDecimalFloat.sol` imports `Float` type for one error

**File:** `src/error/ErrDecimalFloat.sol` line 5

The error file imports the `Float` user-defined type solely for use as the parameter of `ZeroNegativePower(Float b)`. All other errors in this file use raw `int256`/`uint256` parameters. This is a minor style inconsistency but may be intentional to preserve semantic meaning in the error signature.

**Recommendation:** No action strictly required. If uniformity is desired, the parameter could be changed to `bytes32` (the underlying type of `Float`), removing the import dependency. However, using `Float` improves developer experience when decoding revert data.

---

## Summary

| ID | Severity | File | Title |
|----|----------|------|-------|
| A07-01 | LOW | `src/lib/deploy/LibDecimalFloatDeploy.sol` | 7 unused imports |
| A01-01 | LOW | `src/concrete/DecimalFloat.sol` | `require` with string instead of custom error |
| A01-02 | INFO | `src/concrete/DecimalFloat.sol` | Missing blank line / extra blank line in NatSpec |
| A01-03 | INFO | `test/` (74 files) | Bare `"src/"` import paths break as git submodule |
| A01-04 | INFO | Multiple | Pragma version split (intentional) |
| A02-01 | INFO | `src/error/ErrDecimalFloat.sol` | Float import for single error parameter |
| A05-01 | INFO | `src/generated/LogTables.pointers.sol` | Zero-value `BYTECODE_HASH` never used |

**No HIGH or MEDIUM findings.**
**No commented-out code found.**
**No build warnings detected** (forge build was not executable in this session; the codebase compiles cleanly based on prior CI evidence from recent commits).
