# Audit Pass 2 -- Test Coverage: `src/lib/LibDecimalFloat.sol`

**Auditor agent:** A06
**Date:** 2026-03-10
**Library:** `LibDecimalFloat` (line 44, `src/lib/LibDecimalFloat.sol`)

---

## Evidence of reading

Source file: `src/lib/LibDecimalFloat.sol` (797 lines total)

### Constants (lines 47-92)

| Constant | Line |
|---|---|
| `LOG_TABLES_ADDRESS` | 50 |
| `FLOAT_ZERO` | 53 |
| `FLOAT_ONE` | 56 |
| `FLOAT_HALF` | 60 |
| `FLOAT_TWO` | 64 |
| `FLOAT_MAX_POSITIVE_VALUE` | 68 |
| `FLOAT_MIN_POSITIVE_VALUE` | 74 |
| `FLOAT_MAX_NEGATIVE_VALUE` | 80 |
| `FLOAT_MIN_NEGATIVE_VALUE` | 86 |
| `FLOAT_E` | 91 |

### Functions (lines 104-795)

| # | Function | Line | Signature |
|---|---|---|---|
| 1 | `fromFixedDecimalLossy` | 104 | `(uint256 value, uint8 decimals) -> (int256, int256, bool)` |
| 2 | `fromFixedDecimalLossyPacked` | 132 | `(uint256 value, uint8 decimals) -> (Float, bool)` |
| 3 | `fromFixedDecimalLossless` | 144 | `(uint256 value, uint8 decimals) -> (int256, int256)` |
| 4 | `fromFixedDecimalLosslessPacked` | 158 | `(uint256 value, uint8 decimals) -> Float` |
| 5 | `toFixedDecimalLossy` (parts) | 176 | `(int256, int256, uint8) -> (uint256, bool)` |
| 6 | `toFixedDecimalLossy` (packed) | 254 | `(Float, uint8) -> (uint256, bool)` |
| 7 | `toFixedDecimalLossless` (parts) | 265 | `(int256, int256, uint8) -> uint256` |
| 8 | `toFixedDecimalLossless` (packed) | 286 | `(Float, uint8) -> uint256` |
| 9 | `packLossy` | 299 | `(int256, int256) -> (Float, bool)` |
| 10 | `packLossless` | 358 | `(int256, int256) -> Float` |
| 11 | `unpack` | 373 | `(Float) -> (int256, int256)` |
| 12 | `add` | 388 | `(Float, Float) -> Float` |
| 13 | `sub` | 405 | `(Float, Float) -> Float` |
| 14 | `minus` | 421 | `(Float) -> Float` |
| 15 | `abs` | 440 | `(Float) -> Float` |
| 16 | `mul` | 474 | `(Float, Float) -> Float` |
| 17 | `div` | 491 | `(Float, Float) -> Float` |
| 18 | `inv` | 507 | `(Float) -> Float` |
| 19 | `eq` | 520 | `(Float, Float) -> bool` |
| 20 | `lt` | 531 | `(Float, Float) -> bool` |
| 21 | `gt` | 545 | `(Float, Float) -> bool` |
| 22 | `lte` | 557 | `(Float, Float) -> bool` |
| 23 | `gte` | 569 | `(Float, Float) -> bool` |
| 24 | `integer` | 582 | `(Float) -> Float` |
| 25 | `frac` | 593 | `(Float) -> Float` |
| 26 | `floor` | 603 | `(Float) -> Float` |
| 27 | `ceil` | 621 | `(Float) -> Float` |
| 28 | `pow10` | 652 | `(Float, address) -> Float` |
| 29 | `log10` | 668 | `(Float, address) -> Float` |
| 30 | `pow` | 690 | `(Float, Float, address) -> Float` |
| 31 | `sqrt` | 764 | `(Float, address) -> Float` |
| 32 | `min` | 773 | `(Float, Float) -> Float` |
| 33 | `max` | 781 | `(Float, Float) -> Float` |
| 34 | `isZero` | 788 | `(Float) -> bool` |

### Test files read (28 files)

- `LibDecimalFloat.abs.t.sol`
- `LibDecimalFloat.add.t.sol`
- `LibDecimalFloat.ceil.t.sol`
- `LibDecimalFloat.constants.t.sol`
- `LibDecimalFloat.decimal.t.sol`
- `LibDecimalFloat.decimalLossless.t.sol`
- `LibDecimalFloat.div.t.sol`
- `LibDecimalFloat.eq.t.sol`
- `LibDecimalFloat.floor.t.sol`
- `LibDecimalFloat.frac.t.sol`
- `LibDecimalFloat.gt.t.sol`
- `LibDecimalFloat.gte.t.sol`
- `LibDecimalFloat.integer.t.sol`
- `LibDecimalFloat.inv.t.sol`
- `LibDecimalFloat.isZero.t.sol`
- `LibDecimalFloat.log10.t.sol`
- `LibDecimalFloat.lt.t.sol`
- `LibDecimalFloat.lte.t.sol`
- `LibDecimalFloat.max.t.sol`
- `LibDecimalFloat.min.t.sol`
- `LibDecimalFloat.minus.t.sol`
- `LibDecimalFloat.mixed.t.sol`
- `LibDecimalFloat.mul.t.sol`
- `LibDecimalFloat.pack.t.sol`
- `LibDecimalFloat.pow.t.sol`
- `LibDecimalFloat.pow10.t.sol`
- `LibDecimalFloat.sqrt.t.sol`
- `LibDecimalFloat.sub.t.sol`

---

## Coverage summary

| Function | Has dedicated test? | Fuzz? | Edge cases? | Error paths? | Notes |
|---|---|---|---|---|---|
| `fromFixedDecimalLossy` | Yes (`decimal.t.sol`) | Yes | Yes (max int256, overflow) | N/A (no revert) | Well covered |
| `fromFixedDecimalLossyPacked` | Yes (`decimal.t.sol`) | Yes | Partial | N/A | Tests pack + lossy flag consistency |
| `fromFixedDecimalLossless` | Yes (`decimalLossless.t.sol`) | Yes | Yes | Yes (revert on lossy) | Well covered |
| `fromFixedDecimalLosslessPacked` | Yes (`decimalLossless.t.sol`) | Yes | Yes | Yes | Well covered |
| `toFixedDecimalLossy` (parts) | Yes (`decimal.t.sol`) | Yes | Yes (negative, zero, underflow, overflow, truncation) | Yes | Well covered |
| `toFixedDecimalLossy` (packed) | Yes (`decimal.t.sol`) | Yes | Via `testToFixedDecimalLossyPacked` | Yes | Consistency test with parts variant |
| `toFixedDecimalLossless` (parts) | Yes (`decimalLossless.t.sol`) | Yes | Yes | Yes (revert on lossy) | Well covered |
| `toFixedDecimalLossless` (packed) | Yes (`decimalLossless.t.sol`) | Yes | Via `testToFixedDecimalLosslessPacked` | Yes | Consistency test |
| `packLossy` | Yes (`pack.t.sol`) | Yes (round trip) | Yes (zero, exponent overflow, negative exponent lossy zero) | Yes (ExponentOverflow) | See finding A06-1 |
| `packLossless` | Indirect only | N/A | N/A | **NO** | See finding A06-2 |
| `unpack` | Yes (`pack.t.sol`) | Yes (round trip) | Yes | N/A | Covered via round-trip |
| `add` | Yes (`add.t.sol`) | Yes | Via fuzz | Via try/catch | Good -- consistency test with parts variant |
| `sub` | Yes (`sub.t.sol`) | Yes | Via fuzz | Via try/catch | Good -- consistency test |
| `minus` | Yes (`minus.t.sol`) | Yes | Via fuzz | Via try/catch | Good |
| `abs` | Yes (`abs.t.sol`) | Yes | Yes (non-negative, negative, min value shift) | N/A | Well covered |
| `mul` | Yes (`mul.t.sol`) | Yes | Via fuzz | Via try/catch | Consistency test |
| `div` | Yes (`div.t.sol`) | Yes | Yes (div by one, div by negative one) | Via try/catch | Good |
| `inv` | Yes (`inv.t.sol`) | Yes | Via fuzz | Via try/catch | Consistency test |
| `eq` | Yes (`eq.t.sol`) | Yes | Yes (zeros, cross-check with lt/gt) | Via try/catch | Good |
| `lt` | Yes (`lt.t.sol`) | Yes + reference | Yes (same, zero, negative vs positive, exponent overflow) | N/A | Well covered with reference implementation |
| `gt` | Yes (`gt.t.sol`) | Yes + reference | Yes (same, zero, negative vs positive, exponent overflow) | N/A | Well covered |
| `lte` | Yes (`lte.t.sol`) | Yes + reference | Yes (same, zero, signs) | N/A | Well covered |
| `gte` | Yes (`gte.t.sol`) | Yes + reference | Yes (same, zero, signs) | N/A | Well covered |
| `integer` | Yes (`integer.t.sol`) | Yes | Yes (examples with positives, negatives, int224 min/max) | N/A | Well covered |
| `frac` | Yes (`frac.t.sol`) | Yes | Yes (non-negative exponent, below -76, examples) | N/A | Well covered |
| `floor` | Yes (`floor.t.sol`) | Yes | Yes (non-negative exp, below -76, negative values, examples) | N/A | Well covered |
| `ceil` | Yes (`ceil.t.sol`) | Yes | Yes (non-negative exp, below -76, examples) | N/A | Well covered |
| `pow10` | Yes (`pow10.t.sol`) | Yes | Via fuzz + ExponentOverflow handling | Yes | Good |
| `log10` | Yes (`log10.t.sol`) | Yes | Via fuzz | Via try/catch | Good |
| `pow` | Yes (`pow.t.sol`) | Yes | Yes (b=0, a=0, a<0, b=1, a<0 b<0, b<0, round trip) | Yes (ZeroNegativePower, PowNegativeBase) | Well covered |
| `sqrt` | Yes (`sqrt.t.sol`) | Yes | Yes (zero, negative, round trip) | Yes (PowNegativeBase) | Good |
| `min` | Yes (`min.t.sol`) | Yes (identity, commutativity, lt, gt) | N/A | N/A | Good |
| `max` | Yes (`max.t.sol`) | Yes (identity, commutativity, lt, gt) | N/A | N/A | Good |
| `isZero` | Yes (`isZero.t.sol`) | Yes | Yes (wrapped zero, packed zero, any exponent, nonzero) | N/A | Well covered |
| Constants | Yes (`constants.t.sol`) | Partial fuzz | Yes (boundary checks via lte/gte, abs) | N/A | Good |

---

## Findings

### A06-1 `packLossless` has no direct test for `CoefficientOverflow` revert [LOW]

**File:** `src/lib/LibDecimalFloat.sol` lines 358-364
**Test file:** `test/src/lib/LibDecimalFloat.pack.t.sol`

`packLossless` wraps `packLossy` and reverts with `CoefficientOverflow` when `lossless` is false. The pack test file (`LibDecimalFloat.pack.t.sol`) only tests `packLossy`: round-trip, zero, exponent overflow, and negative-exponent lossy zero. There is no test that calls `packLossless` directly and asserts that it reverts with `CoefficientOverflow` when the coefficient does not fit in `int224`.

`packLossless` is used pervasively throughout other tests as a helper (187 call sites across 18 test files), but always with values known to fit. No test exercises the revert path.

**Impact:** The `CoefficientOverflow` error path in `packLossless` is untested. A regression that breaks this revert (e.g., changing the error selector, forgetting to check the lossless flag) would not be caught by the pack test suite.

### A06-2 `packLossy` lossy-but-packable path lacks targeted test [LOW]

**File:** `src/lib/LibDecimalFloat.sol` lines 313-326
**Test file:** `test/src/lib/LibDecimalFloat.pack.t.sol`

When a coefficient does not fit in `int224` but is not so extreme that the exponent overflows, `packLossy` enters a loop that divides the coefficient by 10 and increments the exponent until it fits (lines 314-325). There is also a fast-path for very large coefficients (`/ 1e72`, line 314-317). The test file contains:
- `testPartsRoundTrip` -- uses `int224` inputs, so the lossy path is never triggered.
- `testPackExponentOverflow` -- triggers the exponent overflow revert, but does not test successful lossy packing.
- `testPackNegativeExponentLossyZero` -- triggers the lossy-zero fallback for very negative exponents.

There is no test that provides a coefficient larger than `int224` range, confirms the function returns `(float, false)` with a correctly truncated coefficient, and then verifies that unpacking the result yields a numerically close value.

**Impact:** The core lossy-packing truncation loop is exercised only indirectly through other function tests (add, mul, etc.). A bug in the fast-path divider (`1e72` threshold at line 314) or the truncation loop could go undetected in the unit test for pack.

### A06-3 `pow` exponentiation-by-squaring loop untested at integer/fraction boundary [INFO]

**File:** `src/lib/LibDecimalFloat.sol` lines 716-734
**Test file:** `test/src/lib/LibDecimalFloat.pow.t.sol`

The `pow` function splits `b` into integer and fractional parts (line 717), then performs exponentiation-by-squaring for the integer part and uses `10^(fraction * log10(a))` for the fractional part, multiplying them together. The test suite exercises:
- `b = 0` (returns 1)
- `b = 1` (identity)
- `b < 0` (recursive call with `inv`)
- Negative base (revert)
- Fuzz round-trip

However, there are no targeted tests for the boundary where `b` is a large integer with no fractional part, verifying the squaring loop alone produces the correct result without the log/pow10 approximation path contributing error. The fuzz round-trip test uses a tolerance of 0.09 (9%), which is quite generous.

**Impact:** Informational. The existing round-trip fuzz test provides broad coverage, but a targeted test could more precisely validate the squaring loop independently.

### A06-4 `floor`/`ceil` not tested with `int224.min` coefficient and negative exponent [INFO]

**File:** `src/lib/LibDecimalFloat.sol` lines 603-643
**Test files:** `test/src/lib/LibDecimalFloat.floor.t.sol`, `test/src/lib/LibDecimalFloat.ceil.t.sol`

`floor` has a subtraction path for negative coefficients with a fractional part (line 613: `sub(i, exponent, 1e76, -76)`). `ceil` has an addition path for positive coefficients with a fractional part (line 638: `add(i, exponent, 1e76, -76)`).

The floor test uses `int224.min` with exponent `0` (identity case) but not with fractional exponents. Similarly, the ceil test uses `type(int224).max` with exponent `0` only.

The extreme case of `floor(int224.min, -1)` requires subtracting 1 from the integer part of the most negative representable coefficient. The fuzz tests `testFloorInRangeNegative` and `testCeilInRange` do cover this range via fuzzing over `int224`, so it is likely exercised by the fuzzer, but there is no explicit targeted example.

**Impact:** Informational. The fuzz tests likely catch issues here, but an explicit example for the extreme coefficient values combined with fractional exponents would strengthen confidence.

### A06-5 No explicit test for `add`/`sub`/`mul` lossy packing via packed API [INFO]

**File:** `src/lib/LibDecimalFloat.sol` lines 388-413, 474-500
**Test files:** `test/src/lib/LibDecimalFloat.add.t.sol`, `test/src/lib/LibDecimalFloat.sub.t.sol`, `test/src/lib/LibDecimalFloat.mul.t.sol`

The packed-API arithmetic functions (`add(Float, Float)`, `sub(Float, Float)`, `mul(Float, Float)`) call `packLossy` on the result, silently discarding the lossless flag. The tests verify consistency between the packed and unpacked APIs but do not test what happens when the arithmetic result is too large for `int224` and must be lossy-packed. For example, multiplying two large packed floats whose product coefficient exceeds `int224` range.

The fuzz tests do generate random `Float` values which can trigger this, but there is no explicit targeted test.

**Impact:** Informational. The consistency fuzz tests handle this implicitly through random input generation.
