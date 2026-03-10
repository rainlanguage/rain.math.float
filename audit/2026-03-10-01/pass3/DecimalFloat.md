# Audit Pass 3 -- Documentation

## File: `src/concrete/DecimalFloat.sol`

**Agent:** A01
**Date:** 2026-03-10

## Evidence of Thorough Reading

**Contract name:** `DecimalFloat`

### Constants (with line numbers)

| Name | Line | Visibility |
|------|------|-----------|
| `FORMAT_DEFAULT_SCIENTIFIC_MIN` | 14 | public |
| `FORMAT_DEFAULT_SCIENTIFIC_MAX` | 19 | public |

### Functions (with line numbers)

| # | Function | Line | Visibility | Mutability |
|---|----------|------|-----------|------------|
| 1 | `maxPositiveValue()` | 24 | external | pure |
| 2 | `minPositiveValue()` | 30 | external | pure |
| 3 | `maxNegativeValue()` | 36 | external | pure |
| 4 | `minNegativeValue()` | 42 | external | pure |
| 5 | `zero()` | 48 | external | pure |
| 6 | `e()` | 54 | external | pure |
| 7 | `parse(string)` | 64 | external | pure |
| 8 | `format(Float,Float,Float)` | 78 | public | pure |
| 9 | `format(Float,bool)` | 89 | external | pure |
| 10 | `format(Float)` | 97 | external | pure |
| 11 | `add(Float,Float)` | 105 | external | pure |
| 12 | `sub(Float,Float)` | 113 | external | pure |
| 13 | `minus(Float)` | 120 | external | pure |
| 14 | `abs(Float)` | 127 | external | pure |
| 15 | `mul(Float,Float)` | 135 | external | pure |
| 16 | `div(Float,Float)` | 143 | external | pure |
| 17 | `inv(Float)` | 150 | external | pure |
| 18 | `eq(Float,Float)` | 158 | external | pure |
| 19 | `lt(Float,Float)` | 166 | external | pure |
| 20 | `gt(Float,Float)` | 175 | external | pure |
| 21 | `lte(Float,Float)` | 184 | external | pure |
| 22 | `gte(Float,Float)` | 193 | external | pure |
| 23 | `integer(Float)` | 200 | external | pure |
| 24 | `frac(Float)` | 207 | external | pure |
| 25 | `floor(Float)` | 214 | external | pure |
| 26 | `ceil(Float)` | 221 | external | pure |
| 27 | `pow10(Float)` | 228 | external | view |
| 28 | `log10(Float)` | 235 | external | view |
| 29 | `pow(Float,Float)` | 243 | external | view |
| 30 | `sqrt(Float)` | 250 | external | view |
| 31 | `min(Float,Float)` | 258 | external | pure |
| 32 | `max(Float,Float)` | 266 | external | pure |
| 33 | `isZero(Float)` | 273 | external | pure |
| 34 | `fromFixedDecimalLossless(uint256,uint8)` | 284 | external | pure |
| 35 | `fromFixedDecimalLossy(uint256,uint8)` | 305 | external | pure |
| 36 | `toFixedDecimalLossless(Float,uint8)` | 293 | external | pure |
| 37 | `toFixedDecimalLossy(Float,uint8)` | 316 | external | pure |

**Total: 2 constants, 37 functions.**

## NatSpec Coverage Analysis

### Contract-Level Documentation

The contract itself (`contract DecimalFloat`) has **no NatSpec** -- no `@title`, `@notice`, `@author`, or `@dev` annotations. This is a finding.

### Function-Level Documentation

Every one of the 37 functions has at least a `///` NatSpec comment. All have `@param` and `@return` documentation for their parameters and return values.

### Detailed Accuracy Review

| Function | Has NatSpec | Has @param | Has @return | Accurate | Notes |
|----------|:-----------:|:----------:|:-----------:|:--------:|-------|
| `maxPositiveValue` | Yes | N/A | Yes | Yes | |
| `minPositiveValue` | Yes | N/A | Yes | Yes | |
| `maxNegativeValue` | Yes | N/A | Yes | Yes | |
| `minNegativeValue` | Yes | N/A | Yes | Yes | |
| `zero` | Yes | N/A | Yes | Yes | |
| `e` | Yes | N/A | Yes | Yes | |
| `parse` | Yes | Yes | Yes | Yes | |
| `format(Float,Float,Float)` | Yes | Yes (partial) | Yes | No | `scientificMin` and `scientificMax` params documented but `a` references absolute value logic correctly |
| `format(Float,bool)` | Yes | Yes | Yes | Yes | |
| `format(Float)` | Yes | Yes | Yes | Yes | |
| `add` | Yes | Yes | Yes | Yes | |
| `sub` | Yes | Yes | Yes | No | See A01-10 |
| `minus` | Yes | Yes | Yes | Yes | |
| `abs` | Yes | Yes | Yes | Yes | |
| `mul` | Yes | Yes | Yes | Yes | |
| `div` | Yes | Yes | Yes | No | See A01-11 |
| `inv` | Yes | Yes | Yes | Yes | |
| `eq` | Yes | Yes | Yes | Yes | |
| `lt` | Yes | Yes | Yes | Yes | |
| `gt` | Yes | Yes | Yes | Yes | |
| `lte` | Yes | Yes | Yes | Yes | |
| `gte` | Yes | Yes | Yes | Yes | |
| `integer` | Yes | Yes | Yes | Yes | |
| `frac` | Yes | Yes | Yes | Yes | |
| `floor` | Yes | Yes | Yes | Yes | |
| `ceil` | Yes | Yes | Yes | Yes | |
| `pow10` | Yes | Yes | Yes | No | See A01-12 |
| `log10` | Yes | Yes | Yes | Yes | |
| `pow` | Yes | Yes | Yes | Partial | Missing period at end of @return on L242 (trivial) |
| `sqrt` | Yes | Yes | Yes | Yes | |
| `min` | Yes | Yes | Yes | Yes | |
| `max` | Yes | Yes | Yes | Yes | |
| `isZero` | Yes | Yes | Yes | Yes | |
| `fromFixedDecimalLossless` | Yes | Yes | Yes | Yes | |
| `fromFixedDecimalLossy` | Yes | Yes | Yes | Yes | |
| `toFixedDecimalLossless` | Yes | Yes | Yes | Yes | |
| `toFixedDecimalLossy` | Yes | Yes | Yes | Yes | |

## Findings

### A01-10 (LOW) -- `sub` parameter NatSpec is ambiguous

**File:** `src/concrete/DecimalFloat.sol` L109-112

The NatSpec for `sub(Float a, Float b)` reads:
- `@param a The first float to subtract.`
- `@param b The second float to subtract.`

This is ambiguous. The function computes `a - b`, meaning `a` is the minuend and `b` is the subtrahend. The current wording could be interpreted as subtracting `a` from something, or subtracting something from `a`. It should clarify the relationship, e.g., `@param a The float to subtract from.` and `@param b The float to subtract.`

### A01-11 (LOW) -- `div` parameter NatSpec is ambiguous

**File:** `src/concrete/DecimalFloat.sol` L139-142

The NatSpec for `div(Float a, Float b)` reads:
- `@param a The first float to divide.`
- `@param b The second float to divide.`

This is ambiguous. The function computes `a / b`, meaning `a` is the dividend and `b` is the divisor. The phrase "The second float to divide" does not convey that `b` is the value being divided by. It should say something like `@param a The dividend.` and `@param b The divisor.`

### A01-12 (LOW) -- `pow10` NatSpec is misleading about what the function computes

**File:** `src/concrete/DecimalFloat.sol` L225-228

The NatSpec reads:
```
/// @param a The float to raise to the power of 10.
/// @return The result of raising the float to the power of 10.
```

This describes `a^10` (a raised to the power of 10). However, the function actually computes `10^a` (10 raised to the power of a), as confirmed by the implementation in `LibDecimalFloatImplementation.pow10` (line 891: "10^x for a float x"). The NatSpec should read something like:
- `@param a The exponent for base-10 exponentiation.`
- `@return The result of 10^a.`

### A01-13 (INFORMATIONAL) -- Contract lacks top-level NatSpec

**File:** `src/concrete/DecimalFloat.sol` L9

The `contract DecimalFloat` declaration has no NatSpec documentation (`@title`, `@notice`, `@author`, or `@dev`). Adding a brief description of the contract's purpose (exposing library functions for offchain/revm consumption) would improve discoverability and developer experience.

### A01-14 (INFORMATIONAL) -- `pow` return NatSpec missing trailing period

**File:** `src/concrete/DecimalFloat.sol` L242

The `@return` annotation reads: `The result of raising the base float to the power of the exponent` -- missing a trailing period, inconsistent with other `@return` annotations in the same file that end with a period.

### A01-15 (INFORMATIONAL) -- `e()` function has NatSpec comment separated from function by blank line

**File:** `src/concrete/DecimalFloat.sol` L51-54

The NatSpec comment block for `e()` is separated from the function definition by a blank line (line 53). NatSpec is conventionally placed immediately above the function signature. While this does not break compilation, it is inconsistent with every other function in the file and could cause documentation generators to fail to associate the comment with the function.
