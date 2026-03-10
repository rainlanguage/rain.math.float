# Audit Pass 1 (Security) - LibDecimalFloatImplementation.sol

**Auditor:** A09
**File:** `src/lib/implementation/LibDecimalFloatImplementation.sol`
**Lines:** 1307

## Evidence of Thorough Reading

### Library
- `LibDecimalFloatImplementation` (line 52)

### Constants (file-level)
| Name | Line | Type |
|------|------|------|
| `ADD_MAX_EXPONENT_DIFF` | 24 | `uint256` (76) |
| `EXPONENT_MAX` | 29 | `int256` (type(int256).max / 2) |
| `EXPONENT_MIN` | 34 | `int256` (-EXPONENT_MAX) |
| `MAXIMIZED_ZERO_SIGNED_COEFFICIENT` | 37 | `int256` (0) |
| `MAXIMIZED_ZERO_EXPONENT` | 40 | `int256` (0) |
| `LOG10_Y_EXPONENT` | 44 | `int256` (-76) |

### Error (file-level)
| Name | Line |
|------|------|
| `WithTargetExponentOverflow` | 21 |

### Imported Errors
`ExponentOverflow`, `Log10Negative`, `Log10Zero`, `MulDivOverflow`, `DivisionByZero`, `MaximizeOverflow` (lines 6-11)

### Imported Constants
`LOG_TABLE_SIZE_BYTES`, `LOG_TABLE_SIZE_BASE`, `LOG_MANTISSA_LAST_INDEX`, `ANTILOG_IDX_LAST_INDEX` (lines 14-17)

### Functions
| Function | Line | Visibility | Mutability |
|----------|------|------------|------------|
| `minus` | 71 | internal | pure |
| `absUnsignedSignedCoefficient` | 89 | internal | pure |
| `unabsUnsignedMulOrDivLossy` | 116 | internal | pure |
| `mul` | 160 | internal | pure |
| `div` | 272 | internal | pure |
| `mul512` | 466 | internal | pure |
| `mulDiv` | 479 | internal | pure |
| `add` | 610 | internal | pure |
| `sub` | 703 | internal | pure |
| `eq` | 724 | internal | pure |
| `inv` | 736 | internal | pure |
| `lookupLogTableVal` | 744 | internal | view |
| `log10` | 783 | internal | view |
| `pow10` | 902 | internal | view |
| `maximize` | 957 | internal | pure |
| `maximizeFull` | 1011 | internal | pure |
| `compareRescale` | 1047 | internal | pure |
| `withTargetExponent` | 1127 | internal | pure |
| `intFrac` | 1169 | internal | pure |
| `mantissa4` | 1197 | internal | pure |
| `lookupAntilogTableY1Y2` | 1227 | internal | view |
| `unitLinearInterpolation` | 1267 | internal | pure |

### Assembly Blocks
1. `mul` line 166-168: zero check
2. `mul512` lines 470-474: 512-bit multiply (CRT-based)
3. `mulDiv` lines 500-507: remainder subtraction
4. `mulDiv` lines 516-529: power-of-two factoring
5. `add` lines 618-620: zero check
6. `add` lines 673-677: overflow detection
7. `compareRescale` lines 1060-1071: no-op rescale check
8. `compareRescale` lines 1092-1094: overflow check
9. `lookupLogTableVal` lines 748-769: table read via extcodecopy
10. `lookupAntilogTableY1Y2` lines 1237-1253: table read via extcodecopy (with internal Yul function)

---

## Findings

### A09-1: `unabsUnsignedMulOrDivLossy` missing exponent overflow check on `exponent + 1` (LOW)

**Location:** Lines 132, 144

**Description:**
When `signedCoefficientAbs` exceeds `type(int256).max` and is not the exact `type(int256).min` value, the function divides by 10 and increments `exponent` by 1. These lines are in checked arithmetic (not within an `unchecked` block), so if `exponent == type(int256).max`, the `exponent + 1` will revert with a raw `Panic(0x11)` instead of the project's custom `ExponentOverflow` error.

This contrasts with the pattern in `minus` (line 75) and `add` (line 680) where `exponent == type(int256).max` is explicitly checked before incrementing.

**Impact:** Low. Through the packed Float API (32-bit exponents from `unpack`), exponents cannot reach `type(int256).max`. The `mul` and `div` functions call this with computed exponents that include additive adjustments, but these stay far below `type(int256).max` for any reasonable input. If somehow reached, the revert is a `Panic(0x11)` rather than a descriptive error, which complicates off-chain debugging and error handling but does not cause incorrect results.

**Recommendation:** Add an explicit exponent overflow check (or document the invariant that callers guarantee bounded exponents) at lines 132 and 144, consistent with the pattern used elsewhere.

---

### A09-2: `mul` adjustExponent comment `[0, 76]` is incorrect; actual maximum is 77 (INFORMATIONAL)

**Location:** Line 208

**Description:**
The comment `// adjustExponent [0, 76]` is inaccurate. The maximum 512-bit product occurs when both absolute coefficients are `2^255` (the abs of `type(int256).min`). The high word `prod1` would be `2^254 ~ 2.89e76`. Tracing through the binary divisions:
- `2.89e76 / 1e37 ~ 2.89e39` (adjust = 37)
- `2.89e39 / 1e18 ~ 2.89e21` (adjust = 55)
- `2.89e21 / 1e9 ~ 2.89e12` (adjust = 64)
- `2.89e12 / 1e4 ~ 2.89e8` (adjust = 68)
- The while loop adds 9 more iterations (adjust = 77)

The actual range is `[0, 77]`. This does not cause a functional issue because `int256(77)` is valid and `10^77 < 2^256`. However, the inaccurate comment could mislead future maintainers.

**Impact:** None. Pure documentation issue.

---

### A09-3: `EXPONENT_MAX` and `EXPONENT_MIN` constants defined but never enforced in production code (INFORMATIONAL)

**Location:** Lines 29, 34

**Description:**
`EXPONENT_MAX` (`type(int256).max / 2`) and `EXPONENT_MIN` (`-EXPONENT_MAX`) are defined and used in test fuzzing bounds but are never checked or enforced in any production function. The implementation functions accept full `int256` exponents.

This is safe in practice because the public API uses packed Float with 32-bit signed exponents (range `[-2^31, 2^31-1]`), and `maximize` adjusts exponents by at most ~77. The resulting exponent range is well within `int256` without overflow risk.

**Impact:** None for the current call graph. These constants serve as documentation of the intended safe range but are enforced only by convention (and test bounding), not by code.

---

### A09-4: `div` unchecked exponent subtraction at line 435 can wrap for extreme `int256` exponents (INFORMATIONAL)

**Location:** Line 435

**Description:**
The expression `exponent = exponentA + underflowExponentBy - exponentB` is in an `unchecked` block. The underflow detection at lines 430-433 only guards the case where `exponentA < 0 && exponentB > 0`. When `exponentA > 0 && exponentB < 0` (which makes the subtraction even larger), the underflow check is skipped because the comment says "This is the only case that can underflow." While true for subtraction underflow, the converse case (large positive difference wrapping) is also possible with extreme `int256` exponents.

Example: `exponentA = type(int256).max - 76` and `exponentB = type(int256).min + 76` would produce a wrapping subtraction.

**Impact:** None via the public API. The packed Float type constrains exponents to 32-bit signed values. After `maximize` adjustments (~77 digits), the effective exponent range is approximately `[-2^31 - 77, 2^31 + 77]`, making this wrapping unreachable. This is an internal-only concern that would only matter if these implementation functions were called with arbitrary `int256` exponents from new code paths.

---

### A09-5: `mul512` and `mulDiv` correctness verification (NO FINDING)

**Location:** Lines 466-555

**Description:**
These functions are standard implementations of the well-known Remco Bloemen 512-bit multiply and mulDiv algorithm, widely audited in OpenZeppelin, PRB Math, and Solady. The implementation was verified line-by-line against OpenZeppelin Math v5.x:

- `mul512` (lines 470-474): CRT-based 512-bit multiplication. Correct.
- `mulDiv` remainder subtraction (lines 500-507): Correct carry handling.
- `mulDiv` power-of-two factoring (lines 516-529): Correct lpotdod computation and division.
- `mulDiv` Newton-Raphson modular inverse (lines 538-547): Six iterations for 256-bit precision. Correct.
- `mulDiv` overflow guard (line 490): `prod1 >= denominator` check. Correct.

No issues found.

---

### A09-6: `add` overflow detection assembly is correct (NO FINDING)

**Location:** Lines 673-677

**Description:**
The overflow detection for signed addition uses the standard pattern: overflow occurs when both operands have the same sign but the result has a different sign. The assembly:
```
let sameSignAB := iszero(shr(0xff, xor(signedCoefficientA, signedCoefficientB)))
let sameSignAC := iszero(shr(0xff, xor(signedCoefficientA, c)))
didOverflow := and(sameSignAB, iszero(sameSignAC))
```
Correctly checks: (A and B have same sign) AND (A and result have different sign). Verified correct.

The recovery path (dividing both by 10 and incrementing exponent) is also sound: after `maximizeFull`, coefficients are in `[1e75, type(int256).max]` (positive) or `[-type(int256).max, -1e75]` (negative). Division by 10 yields values in approximately `[1e74, 1.16e76]`, and the sum of two such values fits in `int256`.

---

### A09-7: `compareRescale` handles unchecked subtraction wrapping correctly (NO FINDING)

**Location:** Lines 1090-1094

**Description:**
The unchecked `exponentDiff = exponentA - exponentB` at line 1090 can wrap for extreme exponent values. However, the subsequent assembly check `slt(exponentDiff, 0)` catches any wrapping (since `exponentA >= exponentB` after the swap, a negative result always indicates wrapping). The `sgt(exponentDiff, 76)` branch handles exponents that are too far apart. Both cases return a comparison result that correctly reflects one operand dominating the other.

---

### A09-8: `lookupLogTableVal` and `lookupAntilogTableY1Y2` memory safety (NO FINDING)

**Location:** Lines 748-769, 1237-1253

**Description:**
Both functions use scratch space (addresses 0x00-0x3f) for `mstore`/`mload` operations around `extcodecopy`. The `memory-safe` annotation is correct:
- `mstore(0, 0)` clears 32 bytes at address 0.
- `extcodecopy` writes 1-2 bytes at positions 30 or 31.
- `mload(0)` reads the value from the low bits.

No memory corruption or free memory pointer issues.

The antilog table lookup does not mask with `0x7FFF` unlike the log table lookup. This is correct because the antilog table values (1000-9977) never have the 0x8000 flag bit set. The log table uses the flag bit to select between alternate small tables, while the antilog table uses a fixed offset for its small table.

---

### A09-9: `maximize` loop termination and precision (NO FINDING)

**Location:** Lines 957-1003

**Description:**
The `maximize` function uses a combination of binary scaling steps (1e38, 1e19, 1e10) and a loop (1e2 steps) to efficiently maximize the coefficient. Each step includes an exponent bounds check (`exponent >= type(int256).min + N`) to prevent underflow.

The final "try multiply by 10" step (lines 995-998) uses a round-trip check (`signedCoefficient == trySignedCoefficient / 10`) to detect overflow. For `type(int256).min`, `type(int256).min * 10` wraps in unchecked arithmetic, but the round-trip check catches this because `wrapped / 10 != type(int256).min`.

The loop at line 981 (`while signedCoefficient / 1e74 == 0`) terminates because each iteration multiplies by 100 and decrements exponent by 2. After at most 37 iterations, the coefficient exceeds 1e74 or the exponent bounds are reached.

---

### A09-10: `minus` handles `type(int256).min` correctly (NO FINDING)

**Location:** Lines 71-83

**Description:**
The function correctly identifies that `-type(int256).min` overflows in two's complement. It handles this by dividing by 10 first (yielding approximately `-5.79e75`) and incrementing the exponent. The lossy division is inherent to the representation change and preserves the numeric value to the maximum precision available. The exponent overflow check at line 75 prevents silent wrapping.

---

## Summary

| ID | Severity | Title |
|----|----------|-------|
| A09-1 | LOW | `unabsUnsignedMulOrDivLossy` missing exponent overflow check on `exponent + 1` |
| A09-2 | INFORMATIONAL | `mul` adjustExponent comment incorrect; actual max is 77 |
| A09-3 | INFORMATIONAL | `EXPONENT_MAX`/`EXPONENT_MIN` defined but never enforced |
| A09-4 | INFORMATIONAL | `div` unchecked exponent subtraction can wrap for extreme int256 exponents |
| A09-5 | NO FINDING | `mul512` and `mulDiv` verified correct |
| A09-6 | NO FINDING | `add` overflow detection verified correct |
| A09-7 | NO FINDING | `compareRescale` unchecked wrapping handled correctly |
| A09-8 | NO FINDING | Table lookup memory safety verified |
| A09-9 | NO FINDING | `maximize` loop termination and precision verified |
| A09-10 | NO FINDING | `minus` handles `type(int256).min` correctly |

Overall assessment: The implementation is well-constructed with careful attention to edge cases in 256-bit and 512-bit arithmetic. The `mulDiv` implementation matches well-audited reference implementations. The primary finding (A09-1) is low severity and relates to error ergonomics rather than correctness. The informational findings relate to documentation accuracy and theoretical edge cases that are unreachable through the public API.
