# Audit Pass 1 (Security) -- `src/concrete/DecimalFloat.sol`

**Auditor:** A01
**Date:** 2026-03-10
**File:** `src/concrete/DecimalFloat.sol` (320 lines)

---

## Evidence of Reading

### Contract

- **`DecimalFloat`** (line 9) -- concrete contract that exposes `LibDecimalFloat`, `LibFormatDecimalFloat`, and `LibParseDecimalFloat` library functions as external/public methods for off-chain (Rust/revm) interop.

### Imports (lines 5-7)

| Import | Source |
|--------|--------|
| `LibDecimalFloat`, `Float` | `../lib/LibDecimalFloat.sol` |
| `LibFormatDecimalFloat` | `../lib/format/LibFormatDecimalFloat.sol` |
| `LibParseDecimalFloat` | `../lib/parse/LibParseDecimalFloat.sol` |

### Constants (lines 12-20)

| Name | Line | Description |
|------|------|-------------|
| `FORMAT_DEFAULT_SCIENTIFIC_MIN` | 14 | `1e-4`, default lower bound for scientific formatting |
| `FORMAT_DEFAULT_SCIENTIFIC_MAX` | 19 | `1e9`, default upper bound for scientific formatting |

### Functions

| Function | Line | Visibility | Mutability | Delegates to |
|----------|------|------------|------------|-------------|
| `maxPositiveValue()` | 24 | external | pure | `LibDecimalFloat.FLOAT_MAX_POSITIVE_VALUE` |
| `minPositiveValue()` | 30 | external | pure | `LibDecimalFloat.FLOAT_MIN_POSITIVE_VALUE` |
| `maxNegativeValue()` | 36 | external | pure | `LibDecimalFloat.FLOAT_MAX_NEGATIVE_VALUE` |
| `minNegativeValue()` | 42 | external | pure | `LibDecimalFloat.FLOAT_MIN_NEGATIVE_VALUE` |
| `zero()` | 48 | external | pure | `LibDecimalFloat.FLOAT_ZERO` |
| `e()` | 54 | external | pure | `LibDecimalFloat.FLOAT_E` |
| `parse(string)` | 64 | external | pure | `LibParseDecimalFloat.parseDecimalFloat` |
| `format(Float, Float, Float)` | 78 | public | pure | `LibFormatDecimalFloat.toDecimalString` |
| `format(Float, bool)` | 89 | external | pure | `LibFormatDecimalFloat.toDecimalString` |
| `format(Float)` | 97 | external | pure | calls `format(Float, Float, Float)` |
| `add(Float, Float)` | 105 | external | pure | `a.add(b)` |
| `sub(Float, Float)` | 113 | external | pure | `a.sub(b)` |
| `minus(Float)` | 120 | external | pure | `a.minus()` |
| `abs(Float)` | 127 | external | pure | `a.abs()` |
| `mul(Float, Float)` | 135 | external | pure | `a.mul(b)` |
| `div(Float, Float)` | 143 | external | pure | `a.div(b)` |
| `inv(Float)` | 150 | external | pure | `a.inv()` |
| `eq(Float, Float)` | 158 | external | pure | `a.eq(b)` |
| `lt(Float, Float)` | 166 | external | pure | `a.lt(b)` |
| `gt(Float, Float)` | 175 | external | pure | `a.gt(b)` |
| `lte(Float, Float)` | 184 | external | pure | `a.lte(b)` |
| `gte(Float, Float)` | 193 | external | pure | `a.gte(b)` |
| `integer(Float)` | 200 | external | pure | `a.integer()` |
| `frac(Float)` | 207 | external | pure | `a.frac()` |
| `floor(Float)` | 214 | external | pure | `a.floor()` |
| `ceil(Float)` | 221 | external | pure | `a.ceil()` |
| `pow10(Float)` | 228 | external | view | `a.pow10(LOG_TABLES_ADDRESS)` |
| `log10(Float)` | 235 | external | view | `a.log10(LOG_TABLES_ADDRESS)` |
| `pow(Float, Float)` | 243 | external | view | `a.pow(b, LOG_TABLES_ADDRESS)` |
| `sqrt(Float)` | 250 | external | view | `a.sqrt(LOG_TABLES_ADDRESS)` |
| `min(Float, Float)` | 258 | external | pure | `a.min(b)` |
| `max(Float, Float)` | 266 | external | pure | `a.max(b)` |
| `isZero(Float)` | 273 | external | pure | `a.isZero()` |
| `fromFixedDecimalLossless(uint256, uint8)` | 284 | external | pure | `LibDecimalFloat.fromFixedDecimalLosslessPacked` |
| `toFixedDecimalLossless(Float, uint8)` | 293 | external | pure | `LibDecimalFloat.toFixedDecimalLossless` |
| `fromFixedDecimalLossy(uint256, uint8)` | 305 | external | pure | `LibDecimalFloat.fromFixedDecimalLossyPacked` |
| `toFixedDecimalLossy(Float, uint8)` | 316 | external | pure | `LibDecimalFloat.toFixedDecimalLossy` |

### Types / Errors / Assembly

- No custom types or errors defined in this file.
- No assembly blocks.
- No state-modifying storage writes.
- No reentrancy vectors (all functions are `pure` or `view` with no external calls except reads from `LOG_TABLES_ADDRESS`).

---

## Security Findings

### A01-3: `require` uses string revert message instead of custom error [LOW]

**Location:** `src/concrete/DecimalFloat.sol`, line 79

**Description:**

```solidity
require(scientificMin.lt(scientificMax), "scientificMin must be less than scientificMax");
```

The entire codebase consistently uses custom errors (defined in `src/error/ErrDecimalFloat.sol` and `src/error/ErrFormat.sol`). This is the only location in the `src/` tree that uses a string-based `require`. String-based reverts:

1. Are more expensive at deployment and at revert time (ABI-encodes the string as `Error(string)`).
2. Are harder to catch and decode programmatically on-chain compared to a 4-byte custom error selector.
3. Break the project's own convention of using custom errors everywhere.

Because this contract is primarily used as an off-chain interop target (Rust/revm calls), the practical on-chain impact is low. However, the inconsistency is a code-quality concern and a minor gas inefficiency.

**Severity:** LOW

**Recommendation:** Define a custom error (e.g., `ScientificMinNotLessThanMax(Float scientificMin, Float scientificMax)`) in the appropriate error file and replace the `require` with a conditional revert.

---

### Summary

| ID | Severity | Title |
|----|----------|-------|
| A01-3 | LOW | `require` uses string revert message instead of custom error |

No MEDIUM, HIGH, or CRITICAL findings. The contract is a thin delegation layer with no storage, no assembly, no reentrancy surface, and no arithmetic of its own. All logic is delegated to the underlying library functions.
