# Audit Pass 4 -- Code Quality: `src/lib/LibDecimalFloat.sol`

**Auditor agent:** A06
**Date:** 2026-03-10
**File:** `src/lib/LibDecimalFloat.sol` (796 lines)

---

## Evidence of thorough reading

### File structure (top to bottom)

| Region | Lines | Content |
|---|---|---|
| SPDX header + pragma | 1-3 | `LicenseRef-DCL-1.0`, `^0.8.25` |
| Imports | 5-14 | 7 error types from `../error/ErrDecimalFloat.sol`; `LibDecimalFloatImplementation` from `./implementation/` |
| Type declaration | 16 | `type Float is bytes32;` |
| Library declaration | 44 | `library LibDecimalFloat` |
| `using` statement | 45 | `using LibDecimalFloat for Float;` |
| Constants | 47-92 | 10 constants: `LOG_TABLES_ADDRESS`, `FLOAT_ZERO`, `FLOAT_ONE`, `FLOAT_HALF`, `FLOAT_TWO`, `FLOAT_MAX_POSITIVE_VALUE`, `FLOAT_MIN_POSITIVE_VALUE`, `FLOAT_MAX_NEGATIVE_VALUE`, `FLOAT_MIN_NEGATIVE_VALUE`, `FLOAT_E` |
| Conversion functions | 104-289 | `fromFixedDecimalLossy`, `fromFixedDecimalLossyPacked`, `fromFixedDecimalLossless`, `fromFixedDecimalLosslessPacked`, `toFixedDecimalLossy` (x2), `toFixedDecimalLossless` (x2) |
| Pack/unpack | 291-379 | `packLossy`, `packLossless`, `unpack` |
| Arithmetic | 381-513 | `add`, `sub`, `minus`, `abs`, `mul`, `div`, `inv` |
| Comparison | 515-575 | `eq`, `lt`, `gt`, `lte`, `gte` |
| Rounding | 577-643 | `integer`, `frac`, `floor`, `ceil` |
| Transcendental | 645-766 | `pow10`, `log10`, `pow`, `sqrt` |
| Min/max/isZero | 768-795 | `min`, `max`, `isZero` |

### Import paths verified

Both imports use relative paths:
- `"../error/ErrDecimalFloat.sol"` -- relative, correct
- `"./implementation/LibDecimalFloatImplementation.sol"` -- relative, correct

**No bare `src/` import paths found.**

### Lint suppression comments catalogued

| Line | Type | Comment |
|---|---|---|
| 59 | slither | `// slither-disable-next-line too-many-digits` (space after `//`) |
| 73 | slither | `// slither-disable-next-line too-many-digits` (space after `//`) |
| 79 | slither | `// slither-disable-next-line too-many-digits` (space after `//`) |
| 85 | slither | `// slither-disable-next-line too-many-digits` (space after `//`) |
| 112 | forge-lint | `// forge-lint: disable-next-line(unsafe-typecast)` |
| 116 | forge-lint | `// forge-lint: disable-next-line(unsafe-typecast)` |
| 190 | forge-lint | `// forge-lint: disable-next-line(unsafe-typecast)` |
| 218 | forge-lint | `// forge-lint: disable-next-line(unsafe-typecast)` |
| 224 | slither | `//slither-disable-next-line divide-before-multiply` (NO space after `//`) |
| 229 | forge-lint | `// forge-lint: disable-next-line(unsafe-typecast)` |
| 306 | forge-lint | `// forge-lint: disable-next-line(unsafe-typecast)` |
| 321 | forge-lint | `// forge-lint: disable-next-line(unsafe-typecast)` |
| 334 | forge-lint | `// forge-lint: disable-next-line(unsafe-typecast)` |
| 584 | slither | `//slither-disable-next-line unused-return` (NO space after `//`) |
| 595 | slither | `//slither-disable-next-line unused-return` (NO space after `//`) |

### Local variable naming for `packLossy` return values

| Function | Local variable | Return |
|---|---|---|
| `add` (395) | `c` | `return c;` |
| `sub` (412) | `c` | `return c;` |
| `minus` (426) | `result` | `return result;` |
| `abs` (449) | `result` | `return result;` |
| `mul` (480) | `c` | `return c;` |
| `div` (498) | `c` | `return c;` |
| `inv` (510) | `result` | `return result;` |
| `integer` (586) | `result` | `return result;` |
| `frac` (597) | `result` | `return result;` |
| `floor` (615) | `result` | `return result;` |
| `ceil` (641) | `result` | `return result;` |
| `pow10` (658) | `result` | `return result;` |
| `log10` (673) | `result` | `return result;` |
| `pow` (748) | `c` | `return c;` |

---

## Findings

### A06-15 Inconsistent slither-disable comment formatting [INFO]

**File:** `src/lib/LibDecimalFloat.sol` lines 59, 73, 79, 85, 224, 584, 595
**Type:** Style inconsistency

The file uses two different formatting styles for slither-disable comments:

1. **With space after `//`** (lines 59, 73, 79, 85):
   ```
   // slither-disable-next-line too-many-digits
   ```

2. **Without space after `//`** (lines 224, 584, 595):
   ```
   //slither-disable-next-line divide-before-multiply
   //slither-disable-next-line unused-return
   ```

Across the broader codebase, both styles are used in `LibDecimalFloatImplementation.sol` as well. Within this file, the spaced form appears 4 times and the unspaced form 3 times. The forge-lint comments are all consistently spaced (`// forge-lint: ...`).

**Impact:** Purely cosmetic. Both forms are functionally equivalent.

### A06-16 `inv` uses unique `(lossless);` suppression pattern instead of `(Float result,)` destructuring [LOW]

**File:** `src/lib/LibDecimalFloat.sol` lines 510-512
**Type:** Style inconsistency / dead code artifact

The `inv` function uniquely binds the `lossless` return value from `packLossy` and then discards it with a bare `(lossless);` expression statement:

```solidity
(Float result, bool lossless) = packLossy(signedCoefficient, exponent);
(lossless);
return result;
```

All 13 other call sites in the file use the standard destructuring pattern that discards the second return value directly:

```solidity
(Float result,) = packLossy(signedCoefficient, exponent);
return result;
```

The `(lossless);` expression on line 511 is dead code -- it evaluates and discards the variable with no side effects. It appears to be a leftover from an earlier implementation that may have used the value or an attempt to suppress an "unused variable" warning using a different technique than the rest of the file.

**Impact:** The dead expression statement is confusing and inconsistent. A reader may wonder whether the author intended to check `lossless` but forgot to add the check. This is LOW because the inconsistency is in public library code where any perceived pattern deviation may be misread as intentional.

### A06-17 Inconsistent local variable naming: `c` vs `result` for packed Float return values [INFO]

**File:** `src/lib/LibDecimalFloat.sol` (14 functions)
**Type:** Style inconsistency

Functions that call `packLossy` and return the packed `Float` use two different naming conventions for the local variable:

- **`c`:** `add`, `sub`, `mul`, `div`, `pow` (5 functions)
- **`result`:** `minus`, `abs`, `inv`, `integer`, `frac`, `floor`, `ceil`, `pow10`, `log10` (9 functions)

The `c` naming appears to originate from the arithmetic functions where `a op b = c`, which is a reasonable convention. However, for unary operations like `minus` and `abs`, `result` is more natural. The inconsistency is that `add` uses `c` but `minus` uses `result`, and `div` uses `c` but `inv` uses `result`, even though `inv` is just `div(1, x)`.

**Impact:** Cosmetic. Does not affect behavior.

### A06-18 Typo in comment: "inaccuraces" should be "inaccuracies" [INFO]

**File:** `src/lib/LibDecimalFloat.sol` line 679
**Type:** Typo

```
/// Due to the inaccuraces of log10 and power10, this is not perfectly
```

The correct spelling "inaccuracies" is used on line 754 in the `sqrt` NatSpec. The same word is misspelled only in the `pow` function NatSpec on line 679.

### A06-19 Doubled word "is is" in comment [INFO]

**File:** `src/lib/LibDecimalFloat.sol` lines 208-209
**Type:** Typo

```
/// Every possible value rounds to 0 if the exponent is less
/// than -77. This is always lossless as we know the value is
/// is not zero in real.
```

"is is" should be "is".

### A06-20 `pow` function directly uses `LibDecimalFloatImplementation` internals, breaking the packed API abstraction [LOW]

**File:** `src/lib/LibDecimalFloat.sol` lines 716-748
**Type:** Leaky abstraction

The `pow` function is the only function in `LibDecimalFloat` that performs multi-step arithmetic by directly calling `LibDecimalFloatImplementation` functions (`intFrac`, `withTargetExponent`, `mul`, `log10`, `pow10`) on unpacked `(int256, int256)` values across many intermediate steps (lines 716-748). All other functions in `LibDecimalFloat` follow a clean pattern:

1. Unpack input(s)
2. Make exactly one call to `LibDecimalFloatImplementation`
3. Pack the result via `packLossy`

The `pow` function instead maintains a 30-line block of raw coefficient/exponent manipulation including an exponentiation-by-squaring loop (lines 722-734), multiple sequential `LibDecimalFloatImplementation.mul` calls, and a `withTargetExponent` call that is cast to `uint256` without a `forge-lint` suppression comment (line 719), unlike the 8 other `unsafe-typecast` suppressions in the file.

This is a valid design choice -- factoring this into `LibDecimalFloatImplementation` would add gas cost for an extra function call boundary. But it creates a maintenance concern: the `pow` function in the public API layer is tightly coupled to internal implementation details, and the missing forge-lint annotation on the `uint256` cast at line 719 is inconsistent with the rest of the file.

**Impact:** If `LibDecimalFloatImplementation` internals change, `pow` would need updating in addition to the implementation library. The mixed abstraction levels within a single function increase cognitive load for reviewers.

### A06-21 `LOG_TABLES_ADDRESS` constant is unused within `LibDecimalFloat.sol` [INFO]

**File:** `src/lib/LibDecimalFloat.sol` line 50
**Type:** Architectural observation

The constant `LOG_TABLES_ADDRESS` is defined inside `library LibDecimalFloat` but never referenced within the file itself. It is consumed exclusively by `src/concrete/DecimalFloat.sol` (lines 229, 236, 244, 251) and tests.

All transcendental functions in `LibDecimalFloat` (`pow10`, `log10`, `pow`, `sqrt`) accept the `tablesDataContract` address as a parameter rather than using the constant. The constant serves as a convenience for callers -- this is a reasonable API design, but it means the library file contains a deployment-specific address that is not used by any logic in the same file.

**Impact:** Informational. The constant could be relocated to `DecimalFloat.sol` or a separate constants file to keep the library purely logic-focused, but the current placement is defensible as it keeps the constant co-located with the type it serves.

---

## Checks with no findings

| Check | Result |
|---|---|
| Bare `src/` import paths | None found. Both imports use relative paths. |
| Commented-out code | None found. All comments are documentation or lint suppressions. |
| Unused imports | All 7 imported error types are used in revert statements. `LibDecimalFloatImplementation` is used throughout. |
| Unreachable branches | None found. All `else` / `else if` branches follow legitimate conditional logic. |
| Dead functions | All 34 functions are exposed through the concrete contract or used internally. |
| Pragma consistency | `^0.8.25` matches all other `src/` files except `DecimalFloat.sol` which uses `=0.8.25`. |

---

## Summary

| Severity | Count | IDs |
|---|---|---|
| LOW | 2 | A06-16, A06-20 |
| INFO | 5 | A06-15, A06-17, A06-18, A06-19, A06-21 |

The file is clean from a code quality perspective. There are no bare `src/` imports, no commented-out code, no dead code, and no unused imports. The two LOW findings are: (1) the `inv` function's unique `(lossless);` dead expression pattern that diverges from the 13 other call sites, and (2) the `pow` function's direct use of implementation internals breaking the otherwise consistent abstraction layer, including a missing forge-lint annotation. The INFO findings are cosmetic: inconsistent slither comment spacing, inconsistent local variable naming, two minor typos, and a constant that lives in the library despite being unused within it.
