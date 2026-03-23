# Audit Pass 5 -- Correctness / Intent Verification: `src/lib/LibDecimalFloat.sol`

**Auditor agent:** A06
**Date:** 2026-03-10
**File:** `src/lib/LibDecimalFloat.sol` (796 lines, 34 functions)

---

## Evidence of thorough reading

### Full function-by-function verification

Every function was read and its implementation traced against its name and NatSpec. Where the function delegates to `LibDecimalFloatImplementation`, the implementation was also read and verified.

| # | Function | Lines | Intent verified | Notes |
|---|----------|-------|-----------------|-------|
| 1 | `fromFixedDecimalLossy` | 104-120 | Yes | Converts `value * 10^(-decimals)` to (coefficient, exponent). Handles overflow of int256 by dividing by 10. |
| 2 | `fromFixedDecimalLossyPacked` | 132-136 | Yes | Wrapper that packs result. Combines lossiness from conversion and packing. |
| 3 | `fromFixedDecimalLossless` | 144-150 | Yes | Reverts if lossy. |
| 4 | `fromFixedDecimalLosslessPacked` | 158-161 | Yes | Wrapper. **NatSpec references nonexistent `fromFixedDecimalLossyMem`** (A06-23). |
| 5 | `toFixedDecimalLossy(int256,int256,uint8)` | 176-242 | Yes | Converts coefficient*10^exponent to fixed-point. Handles negative exponents (division), positive exponents (multiplication), zero exponent (identity). |
| 6 | `toFixedDecimalLossy(Float,uint8)` | 254-257 | Yes | Wrapper that unpacks Float. |
| 7 | `toFixedDecimalLossless(int256,int256,uint8)` | 265-275 | Yes | Reverts if lossy. |
| 8 | `toFixedDecimalLossless(Float,uint8)` | 286-289 | Yes | Wrapper. |
| 9 | `packLossy` | 299-351 | Yes | Truncates coefficient to fit int224, adjusts exponent. Returns lossless flag. Assembly packing verified. |
| 10 | `packLossless` | 358-364 | Yes | Reverts if lossy. |
| 11 | `unpack` | 373-379 | Yes | `signextend(27, ...)` for 224-bit sign extension, `sar(224, ...)` for exponent extraction. Correct inverse of pack. |
| 12 | `add` | 388-397 | Yes | Delegates to `LibDecimalFloatImplementation.add`. Adds a + b. |
| 13 | `sub` | 405-414 | Yes | Delegates to `LibDecimalFloatImplementation.sub` which negates B and adds A + (-B) = A - B. **NatSpec says "Subtract float a from float b" which means b - a, but code computes a - b** (A06-22). |
| 14 | `minus` | 421-428 | Yes | Negates coefficient. Handles int256.min edge case via division. |
| 15 | `abs` | 440-451 | Yes | Negates if negative, identity if non-negative. |
| 16 | `mul` | 474-482 | Yes | Delegates to implementation which multiplies via 512-bit intermediates. |
| 17 | `div` | 491-500 | Yes | Delegates to implementation which divides with maximized coefficients and mulDiv. |
| 18 | `inv` | 507-513 | Yes | Computes 1/x via `div(1e76, -76, x)`. |
| 19 | `eq` | 520-524 | Yes | Rescales and compares coefficients for equality. |
| 20 | `lt` | 531-538 | Yes | Rescales and checks `coeffA < coeffB`. |
| 21 | `gt` | 545-551 | Yes | Rescales and checks `coeffA > coeffB`. |
| 22 | `lte` | 557-563 | Yes | Rescales and checks `coeffA <= coeffB`. |
| 23 | `gte` | 569-575 | Yes | Rescales and checks `coeffA >= coeffB`. |
| 24 | `integer` | 582-588 | Yes | Returns integer part (truncation toward zero). NatSpec correctly describes this as floor for positive, ceil for negative. |
| 25 | `frac` | 593-598 | Yes | Returns fractional part. |
| 26 | `floor` | 603-617 | Yes | Verified with positive (2.7->2), negative (-2.7->-3), integer inputs. Subtracts 1 for negative non-integers. |
| 27 | `ceil` | 621-643 | Yes | Verified with positive (2.7->3), negative (-2.7->-2), zero fraction. Adds 1 for positive non-integers, truncation toward zero handles negative case. |
| 28 | `pow10` | 652-660 | Yes | Computes 10^(input) via antilog table lookup. Name and intent match. **NatSpec references nonexistent `power10` function** (A06-24). |
| 29 | `log10` | 668-675 | Yes | Computes log10(input) via table lookup. **NatSpec self-referential** (A06-24). |
| 30 | `pow` | 690-750 | Yes | Computes a^b. Splits b into integer (exponentiation by squaring) and fractional (10^(frac*log10(a))) parts. Handles 0^0=1, 0^neg=revert, 0^pos=0, neg base=revert, b<0 via inverse. |
| 31 | `sqrt` | 764-766 | Yes | Delegates to `pow(a, FLOAT_HALF)`. sqrt(a) = a^0.5. |
| 32 | `min` | 773-775 | Yes | Returns smaller of two floats. |
| 33 | `max` | 781-783 | Yes | Returns larger of two floats. |
| 34 | `isZero` | 788-795 | Yes | Checks if lower 224 bits are zero. Correct because coefficient == 0 means value is zero regardless of exponent. |

### Constants verification

| Constant | Expected packing | Verified |
|----------|------------------|----------|
| `FLOAT_ZERO` (0x0) | coeff=0, exp=0. Value=0. | Correct |
| `FLOAT_ONE` (0x01) | coeff=1, exp=0. Value=1. | Correct |
| `FLOAT_HALF` (0xffffffff...05) | coeff=5, exp=-1 (0xffffffff = -1 as int32). Value=0.5. | Correct |
| `FLOAT_TWO` (0x02) | coeff=2, exp=0. Value=2. | Correct |
| `FLOAT_MAX_POSITIVE_VALUE` | coeff=int224.max (0x7f...f, 56 hex), exp=int32.max (0x7fffffff). Largest representable value. | Correct |
| `FLOAT_MIN_POSITIVE_VALUE` | coeff=1, exp=int32.min (0x80000000). Smallest positive value. | Correct |
| `FLOAT_MAX_NEGATIVE_VALUE` | coeff=-1 (0xff...f as int224), exp=int32.min. Closest to zero negative value. | Correct |
| `FLOAT_MIN_NEGATIVE_VALUE` | coeff=int224.min (0x80...0), exp=int32.max. Most negative value. | Correct |
| `FLOAT_E` | coeff=2.718...e66, exp=-66 (0xffffffbe = -66 as int32). Euler's number. Verified by test using Solidity literal. | Correct |
| `LOG_TABLES_ADDRESS` | Deterministic deployment address. Not mathematically verifiable from source alone, but tested via deployment scripts. | N/A (deployment constant) |

All 9 mathematical constants are correctly packed. The test file `test/src/lib/LibDecimalFloat.constants.t.sol` independently verifies all 9 by packing the expected (coefficient, exponent) pairs and comparing.

### Comparison function sign-combination analysis

`compareRescale` handles four cases without rescaling (returning raw coefficients):

| Case | Why correct |
|------|-------------|
| Either coefficient is zero | Zero is less than all positives, greater than all negatives, regardless of exponent. Raw coefficient 0 satisfies all comparison operators correctly. |
| Different signs | Positive > negative always, regardless of magnitude. Raw coefficients preserve sign relationship. |
| Equal exponents | Same exponent means coefficient magnitude directly determines ordering. |
| Exponent diff > 76 or overflow | The larger-exponent value dominates; the smaller is effectively zero in comparison. Handled by returning (coeff, 0) or (0, coeff) depending on swap direction. |

All sign combinations for `lt`, `gt`, `lte`, `gte`, `eq` produce correct results through `compareRescale`.

### floor/ceil verification with worked examples

| Input | Function | intFrac result | Adjustment | Output | Expected | Match |
|-------|----------|----------------|------------|--------|----------|-------|
| 2.7 (27, -1) | floor | i=20, f=7 | none (positive) | 2 | 2 | Yes |
| -2.7 (-27, -1) | floor | i=-20, f=-7 | sub 1 (negative + frac) | -3 | -3 | Yes |
| 3.0 (30, -1) | floor | i=30, f=0 | none (no frac) | 3 | 3 | Yes |
| -3.0 (-30, -1) | floor | i=-30, f=0 | none (no frac) | -3 | -3 | Yes |
| 2.7 (27, -1) | ceil | i=20, f=7 | add 1 (positive frac) | 3 | 3 | Yes |
| -2.7 (-27, -1) | ceil | i=-20, f=-7 | none (negative frac = truncation toward zero) | -2 | -2 | Yes |
| 3.0 (30, -1) | ceil | i=30, f=0 | none (no frac) | returns float | 3 | Yes |
| 0.5 (5, -1) | ceil | i=0, f=5 | add 1 | 1 | 1 | Yes |
| -0.5 (-5, -1) | ceil | i=0, f=-5 | none (negative frac) | 0 | 0 | Yes |
| 100 (1, 2) | floor | n/a | exp >= 0, return float | 100 | 100 | Yes |
| 100 (1, 2) | ceil | n/a | exp >= 0, return float | 100 | 100 | Yes |

---

## Findings

### A06-22 `sub` NatSpec says "Subtract float a from float b" but code computes a - b [LOW]

**File:** `src/lib/LibDecimalFloat.sol` line 399
**Type:** NatSpec / intent mismatch

The opening NatSpec line for `sub` reads:

```
/// Subtract float a from float b.
```

The English phrase "Subtract X from Y" means "Y - X". Therefore "Subtract float a from float b" means "b - a".

However, the code computes a - b:
- The implementation calls `LibDecimalFloatImplementation.sub(coeffA, expA, coeffB, expB)`
- That function negates B and adds: `add(A, -B) = A - B`

The @param documentation on lines 403-404 correctly describes the a - b semantics:
- `@param a The float to subtract from.` (minuend)
- `@param b The float to subtract.` (subtrahend)

The opening NatSpec line contradicts both the @param docs and the implementation. Any developer reading only the summary line would expect `sub(a, b)` to return `b - a`.

**Impact:** A caller trusting the NatSpec summary would get the operands backwards, leading to incorrect arithmetic (sign reversal). The @param docs and code are consistent with each other, so a careful reader would catch this, but the summary line is the first thing a developer reads.

### A06-23 `fromFixedDecimalLosslessPacked` NatSpec references nonexistent `fromFixedDecimalLossyMem` [LOW]

**File:** `src/lib/LibDecimalFloat.sol` lines 152-155
**Type:** Stale NatSpec reference

The NatSpec for `fromFixedDecimalLosslessPacked` contains three references to a function called `fromFixedDecimalLossyMem`:

```solidity
/// Lossless version of `fromFixedDecimalLossyMem`. This will revert if the
/// conversion is lossy.
/// @param value As per `fromFixedDecimalLossyMem`.
/// @param decimals As per `fromFixedDecimalLossyMem`.
```

No function named `fromFixedDecimalLossyMem` exists anywhere in the codebase. This appears to be a stale reference from a rename. The function should reference either `fromFixedDecimalLossyPacked` (the packed lossy variant) or `fromFixedDecimalLossy` (the unpacked lossy variant).

**Impact:** A developer following the NatSpec cross-reference will find no matching function, causing confusion about the API surface. Since this is in a `Lossless` variant, a developer may fail to understand the conversion semantics by being unable to find the referenced lossy counterpart.

### A06-24 `pow10` and `log10` NatSpec contain stale/self-referential descriptions [INFO]

**File:** `src/lib/LibDecimalFloat.sol` lines 645, 662
**Type:** Stale NatSpec

The `pow10` NatSpec says:
```
/// Same as power10, but accepts a Float struct instead of separate values.
```
There is no function called `power10` in `LibDecimalFloat`.

The `log10` NatSpec says:
```
/// Same as log10, but accepts a Float struct instead of separate values.
```
This is self-referential -- the function IS `log10`.

Both descriptions follow a pattern from other functions (e.g., `add`, `mul`) where both packed and unpacked API versions existed in the library. For `pow10` and `log10`, only the packed version exists in `LibDecimalFloat` (the unpacked versions live in `LibDecimalFloatImplementation`), making these descriptions vestigial.

**Impact:** Informational. A reader may look for a sibling function that does not exist.

### A06-25 Comment says "always lossless" but code returns lossy flag [INFO]

**File:** `src/lib/LibDecimalFloat.sol` lines 208-209
**Type:** Misleading comment

In `toFixedDecimalLossy`, the comment for the `finalExponent < -77` branch reads:

```solidity
// Every possible value rounds to 0 if the exponent is less
// than -77. This is always lossless as we know the value is
// is not zero in real.
```

The code immediately returns `(0, false)` where `false` means the conversion IS lossy (NOT lossless). The comment appears to say the opposite of what the code does. The intended meaning is likely: "This [rounding to zero] is never lossless [i.e., always lossy], as we know the value is not zero in real [but we return zero]."

Note: The "is is" duplication in this comment was already identified as A06-19 in pass 4.

**Impact:** Informational. The code behavior is correct (`false` = lossy, which is right because a non-zero value is being returned as zero). The comment wording is confusing but does not affect execution.

---

## Checks with no findings

| Check | Result |
|-------|--------|
| `add` computes a + b | Confirmed. Delegates to `LibDecimalFloatImplementation.add(coeffA, expA, coeffB, expB)`. |
| `mul` computes a * b | Confirmed. Delegates to `LibDecimalFloatImplementation.mul`. Uses 512-bit intermediates. |
| `div` computes a / b | Confirmed. Delegates to `LibDecimalFloatImplementation.div(coeffA, expA, coeffB, expB)`. B=0 reverts. |
| `pow10` computes 10^a (not a^10) | Confirmed. Implementation uses antilog table, integer part adjusts exponent. `10^(int+frac) = 10^int * 10^frac`. |
| `pow(a,b)` computes a^b | Confirmed. Uses `a^b = a^(int_b) * 10^(frac_b * log10(a))`. |
| `floor` correct for negative numbers | Confirmed with worked examples. Subtracts 1 from truncated integer when input is negative with non-zero fraction. |
| `ceil` correct for negative numbers | Confirmed. Truncation toward zero (from `intFrac`) already rounds up for negatives. Only adds 1 for positive fractions. |
| `fromFixedDecimal` mathematically correct | Confirmed. `value * 10^(-decimals)` maps to `(value, -decimals)` or `(value/10, -decimals+1)` when value > int256.max. |
| `toFixedDecimal` mathematically correct | Confirmed. `coefficient * 10^(exponent + decimals)` correctly converts to fixed-point. |
| `packLossy` preserves values | Confirmed. Truncates coefficient to fit int224, increments exponent to compensate. Returns lossless flag. Zero returns FLOAT_ZERO. |
| `packLossless` preserves values | Confirmed. Reverts if packLossy returns lossless=false. |
| `unpack` is inverse of `pack` | Confirmed. `signextend(27, ...)` and `sar(224, ...)` correctly reverse the `or(and(...), shl(...))` packing. |
| All 9 mathematical constants correct | Confirmed by manual unpacking of hex values and cross-reference with test file. |
| Comparison functions handle all sign combinations | Confirmed via `compareRescale` analysis: zero, different-sign, same-sign/same-exponent, and same-sign/different-exponent cases all produce correct results. |
| `inv` computes 1/x | Confirmed. Delegates to `div(1e76, -76, x)` = 1/x. |
| `sqrt` computes x^0.5 | Confirmed. Delegates to `pow(a, FLOAT_HALF)`. |
| `min`/`max` correct | Confirmed. Simple ternary on `lt`/`gt`. |
| `isZero` correct | Confirmed. Checks lower 224 bits (coefficient) for zero. Exponent is irrelevant when coefficient is zero. |
| `abs` correct | Confirmed. Identity for non-negative, negation for negative. Handles int224.min via `minus` which divides by 10. |

---

## Summary

| Severity | Count | IDs |
|----------|-------|-----|
| LOW | 2 | A06-22, A06-23 |
| INFO | 2 | A06-24, A06-25 |

The core arithmetic, comparison, rounding, and conversion logic all correctly implement their stated intent. All 9 mathematical constants are correctly encoded. The `floor`/`ceil` functions correctly handle negative numbers. `pow10` computes `10^a` (not `a^10`), `sub(a,b)` computes `a - b` (not `b - a`), and `pow(a,b)` computes `a^b`.

The two LOW findings are both NatSpec issues that could mislead callers:
1. A06-22: `sub`'s opening NatSpec line says the opposite of what the code does ("Subtract a from b" = b-a, but code computes a-b).
2. A06-23: `fromFixedDecimalLosslessPacked` references a nonexistent function name three times.

No correctness bugs were found in the implementation logic.
