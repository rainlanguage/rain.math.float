# Audit Pass 2: Test Coverage -- `src/lib/format/LibFormatDecimalFloat.sol` (A08)

## Evidence of Reading

### Source: `src/lib/format/LibFormatDecimalFloat.sol` (165 lines)

**`countSigFigs(int256 signedCoefficient, int256 exponent)` -- lines 18-50:**
- Line 19: zero coefficient early return (returns 1).
- Lines 25-30: negative exponent -- strip trailing zeros from coefficient.
- Lines 32-35: count digits by dividing coefficient by 10.
- Lines 38-47: adjust for exponent. Negative exponent: sigFigs = max(sigFigs, |exponent|). Positive exponent: sigFigs += exponent.
- Line 49: return.

**`toDecimalString(Float float, bool scientific)` -- lines 58-164:**
- Line 59: unpack float.
- Lines 60-62: zero coefficient early return (returns "0").
- Lines 66-76: scientific mode -- maximizeFull, then scale by 1e76 or 1e75.
- Lines 77-82: non-scientific, positive exponent -- multiply coefficient by 10^exponent (OVERFLOW RISK, A08-1).
- Lines 83-86: non-scientific, negative exponent < -76 -- revert UnformatableExponent.
- Lines 88-92: non-scientific, negative exponent in [-76, -1] -- compute scale.
- Lines 93-96: non-scientific, exponent == 0 -- scaleExponent = 0.
- Lines 99-110: split into integral and fractional parts.
- Lines 112-120: determine sign, make integral/fractional positive.
- Lines 122-148: build fractional string with leading zeros, strip trailing zeros.
- Lines 150-157: build integral string, build exponent string (scientific only).
- Lines 159-163: concatenate prefix, integral, fractional, exponent.

### Test: `LibFormatDecimalFloat.countSigFigs.t.sol` (125 lines)

| Test Function | Lines | Coverage |
|---------------|-------|----------|
| `testCountSigFigsExamples` | 16-111 | Hard-coded examples: zero, positive/negative integers, decimals, trailing zeros, internal zeros, positive exponents. ~50 assertions. |
| `testCountSigFigsZero` (fuzz) | 113-115 | Zero coefficient with any exponent always returns 1. |
| `testCountSigFigsOne` (fuzz) | 117-124 | Coefficient = 10^(-exponent) for exponent in [-76, 0], verifying sigFigs = 1 for both positive and negative. |

### Test: `LibFormatDecimalFloat.toDecimalString.t.sol` (253 lines)

| Test Function | Lines | Coverage |
|---------------|-------|----------|
| `testFormatDecimalRoundTripExamples` | 37-92 | 47 round-trip checks (parse then format). Both scientific and non-scientific. Includes 0, negatives, large coefficients, small fractions, e-76, e76, e200. |
| `testFormatDecimalRoundTripNonNegative` (fuzz) | 95-105 | Fuzz: random non-negative value via `fromFixedDecimalLosslessPacked(value, 18)`, both scientific modes. Round-trip: format -> parse -> eq. Canonicalization check. |
| `testFormatDecimalRoundTripNegative` (fuzz) | 108-125 | Fuzz: negative = minus(positive), verify negative format == "-" + positive format, then parse -> eq. |
| `testFormatDecimalExamples` | 128-252 | ~92 hard-coded format assertions. Covers: scientific with varying exponents, zero with various exponents, non-scientific integers, decimals (0.01, 0.1, 0.101, 1.1), 9-sig-fig formatting, 10-sig-fig scientific, powers of 10, extreme magnitudes. |

### Test: `DecimalFloat.format.t.sol` (43 lines)

| Test Function | Lines | Coverage |
|---------------|-------|----------|
| `testFormatDeployed` (fuzz) | 18-31 | Fuzz: arbitrary Float + scientific bounds. Compares library call vs deployed contract call. Error parity checked via try/catch. |
| `testFormatConstants` | 33-42 | Verifies FORMAT_DEFAULT_SCIENTIFIC_MIN == (1, -4) and FORMAT_DEFAULT_SCIENTIFIC_MAX == (1, 9). |

## Coverage Analysis

### Lines/Branches Covered

| Source Line(s) | Branch/Path | Test Coverage |
|----------------|-------------|---------------|
| 19 (zero coeff) | countSigFigs zero | `testCountSigFigsExamples` line 17, `testCountSigFigsZero` fuzz |
| 25-30 (neg exp strip) | countSigFigs trailing zero strip | `testCountSigFigsExamples` lines 21, 25, 29, 33, etc. |
| 32-35 (digit count) | countSigFigs digit loop | All non-zero examples |
| 38-42 (neg exp adjust) | countSigFigs neg-exp sigfigs | Lines 36-57 (0.1, 0.01, 0.001 examples) |
| 43-46 (pos exp adjust) | countSigFigs pos-exp sigfigs | Lines 106-110 (1e1, 1e2, -1e3) |
| 60-62 (zero return) | toDecimalString zero | `testFormatDecimalExamples` lines 139-145, round-trip lines 41-42 |
| 66-76 (scientific scale) | toDecimalString scientific mode | `testFormatDecimalExamples` lines 130-136, 148-154, 228-232, 235-244 |
| 77-82 (non-sci pos exp) | toDecimalString non-sci positive exponent | `testFormatDecimalExamples` lines 161-162, 167-168, 224-225 (max exp=2) |
| 83-86 (UnformatableExponent) | toDecimalString neg exp < -76 | **NOT TESTED** |
| 88-92 (non-sci neg exp) | toDecimalString non-sci negative exponent | `testFormatDecimalExamples` lines 172-199, 208-223 |
| 93-96 (non-sci exp=0) | toDecimalString non-sci exponent=0 | `testFormatDecimalExamples` lines 160, 166, 220-221 |
| 99-110 (integral/frac split) | toDecimalString split | All non-zero formatted outputs |
| 112-120 (sign handling) | toDecimalString negative values | All negative examples |
| 126-148 (fractional build) | toDecimalString fractional string | Lines 172-199, 208-223, 62-65, 78-81 |
| 150-157 (exponent string) | toDecimalString exponent suffix | Scientific mode examples |
| 155 (displayExponent == 0) | Scientific with displayExponent=0 | `testFormatDecimalExamples` line 157 ("1" for coefficient=1, exp=0) |

### Lines/Branches NOT Covered

| Source Line(s) | Branch/Path | Gap Description |
|----------------|-------------|-----------------|
| 84-85 | `exponent < -76` revert | No test asserts `UnformatableExponent` is thrown |
| 77-82 | Non-scientific with large positive exponent (overflow) | Only tested with exponent up to 2; no test exercises A08-1 overflow |

## Findings

### A08-2 [LOW]: No test for `UnformatableExponent` revert path (line 84-85)

The `toDecimalString` function reverts with `UnformatableExponent(exponent)` when called in non-scientific mode with `exponent < -76` (line 84-85). This is the only explicit error path in the file and it has zero test coverage: no test in any of the three test files calls `toDecimalString` with `scientific=false` and an exponent below -76, and no test uses `vm.expectRevert` with the `UnformatableExponent` selector.

This matters because:
1. If the guard were accidentally removed or the threshold changed, no test would catch the regression.
2. Callers relying on this error for input validation have no specification-level assurance it works.

### A08-3 [LOW]: No test for non-scientific mode with large positive exponents (A08-1 overflow)

Pass 1 finding A08-1 identified that line 80 (`signedCoefficient *= int256(10) ** uint256(exponent)`) can overflow for valid Float values with large positive exponents when `scientific=false`. The existing tests only exercise non-scientific positive exponents up to 2 (e.g., `checkFormat(1, 2, false, "100")`).

There is no test that:
- Exercises the overflow behavior (e.g., `packLossless(type(int224).max, 10)` formatted with `scientific=false`).
- Verifies any guard or expected revert for this path.
- Tests the boundary between formattable and unformattable positive exponents.

This is a coverage gap for the vulnerability identified in A08-1. The fuzz tests (`testFormatDecimalRoundTripNonNegative` and `testFormatDecimalRoundTripNegative`) always create floats via `fromFixedDecimalLosslessPacked(value, 18)`, which produces exponents near -18 after normalization, so they never exercise this path.

### A08-4 [INFO]: `countSigFigs` is not exposed in the concrete contract

`countSigFigs` is defined as `internal pure` and tested directly in `LibFormatDecimalFloat.countSigFigs.t.sol`, but it is not exposed through `DecimalFloat.sol` (the concrete contract). This means it is unavailable for off-chain use via the Rust/WASM layer that calls through the concrete contract. If this is intentional (utility for potential library consumers only), no action needed. If off-chain callers need sig-fig counting, the function should be exposed.

### A08-5 [INFO]: Fuzz tests for `toDecimalString` only exercise fixed-decimal-derived floats

Both fuzz tests (`testFormatDecimalRoundTripNonNegative` at line 95 and `testFormatDecimalRoundTripNegative` at line 108) create floats exclusively via `fromFixedDecimalLosslessPacked(value, 18)`. This constrains the fuzz domain to:
- Coefficients that fit in the normalized form of a uint256 / 1e18 representation.
- Exponents near -18 (after normalization by pack).

This means the fuzzer never explores:
- Large positive exponents (e.g., `(1, 100)` in non-scientific mode).
- Very small negative exponents close to -76 boundary.
- Coefficients near `int224.max` or `int224.min` with non-zero exponents.

A broader fuzz test that generates arbitrary valid packed Float values (random int224 coefficient, random int32 exponent) would significantly improve coverage of edge cases and boundary conditions.

## Summary

| ID | Severity | Description |
|----|----------|-------------|
| A08-2 | LOW | No test for `UnformatableExponent` revert path (line 84-85) |
| A08-3 | LOW | No test for non-scientific mode with large positive exponents (A08-1 overflow) |
| A08-4 | INFO | `countSigFigs` not exposed in concrete contract |
| A08-5 | INFO | Fuzz tests only exercise fixed-decimal-derived floats, missing broad coverage |
