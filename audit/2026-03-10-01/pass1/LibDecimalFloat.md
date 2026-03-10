# Audit Pass 1: Security — `src/lib/LibDecimalFloat.sol` (A06)

**Date:** 2026-03-10 | **File:** 796 lines

## Evidence of Reading

**Library:** `LibDecimalFloat` (line 44) — Main public API library. Defines `Float` UDT wrapping `bytes32`.

**Type:** `Float` (line 16) — Upper 32 bits: int32 exponent, lower 224 bits: int224 coefficient.

**Constants (10):** `LOG_TABLES_ADDRESS` (L50), `FLOAT_ZERO` (L53), `FLOAT_ONE` (L56), `FLOAT_HALF` (L60), `FLOAT_TWO` (L64), `FLOAT_MAX_POSITIVE_VALUE` (L68), `FLOAT_MIN_POSITIVE_VALUE` (L73), `FLOAT_MAX_NEGATIVE_VALUE` (L79), `FLOAT_MIN_NEGATIVE_VALUE` (L85), `FLOAT_E` (L91).

**Functions (32):**
- Conversion: `fromFixedDecimalLossy` (L104), `fromFixedDecimalLossyPacked` (L132), `fromFixedDecimalLossless` (L144), `fromFixedDecimalLosslessPacked` (L158), `toFixedDecimalLossy` (L176, L254), `toFixedDecimalLossless` (L265, L286)
- Packing: `packLossy` (L299), `packLossless` (L358), `unpack` (L373)
- Arithmetic: `add` (L388), `sub` (L405), `minus` (L421), `abs` (L440), `mul` (L474), `div` (L491), `inv` (L507)
- Comparison: `eq` (L520), `lt` (L531), `gt` (L545), `lte` (L557), `gte` (L569)
- Rounding: `integer` (L582), `frac` (L593), `floor` (L603), `ceil` (L621)
- Transcendental: `pow10` (L652), `log10` (L668), `pow` (L690), `sqrt` (L764)
- Utility: `min` (L773), `max` (L781), `isZero` (L788)

**Assembly blocks (3):** `packLossy` (L347-349), `unpack` (L375-378), `isZero` (L790-793)

## Findings

No LOW+ security findings.

### A06-1 [INFO]: Silent precision loss in arithmetic operations without caller notification

All packed arithmetic functions discard the `lossless` bool from `packLossy`. By design and documented. The ~67 decimal digits of int224 precision makes packing-induced loss extremely rare.

### A06-2 [INFO]: `pow` exponentiation-by-squaring loop may consume excessive gas for large integer exponents

The loop iterates O(log2(exponentBInteger)) times with no explicit upper bound. In practice, intermediate overflows cause reverts before gas exhaustion.

## Verified as Correct

- All 3 assembly blocks: pure stack operations, correct signextend/sar usage, no memory safety issues
- Pack/unpack round-trip for edge cases (int224.min, int224.max, negative exponents)
- All 10 constants encode correct values
- `compareRescale` edge cases (zero, different signs, extreme exponent diffs) handled correctly
- `toFixedDecimalLossy` overflow checks correct
- `packLossy` truncation loop and exponent overflow handling correct
- `pow` function flow: negative b recursion, zero base, identity case all correct
- `floor`/`ceil` sign-aware rounding logic correct
