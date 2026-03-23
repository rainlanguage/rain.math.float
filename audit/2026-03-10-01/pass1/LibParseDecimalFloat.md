# Audit Pass 1 (Security) - LibParseDecimalFloat.sol

**Auditor Agent:** A10
**File:** `src/lib/parse/LibParseDecimalFloat.sol`
**Date:** 2026-03-10

## Evidence of Thorough Reading

**Library:** `LibParseDecimalFloat`

### Functions

| Function | Line | Visibility |
|---|---|---|
| `parseDecimalFloatInline(uint256 start, uint256 end)` | 34 | internal pure |
| `parseDecimalFloat(string memory str)` | 169 | internal pure |

### Types / Errors / Constants Defined in File

None defined directly in this file. All types, errors, and constants are imported.

### Imports

| Symbol | Source |
|---|---|
| `LibParseChar` | `rain.string/lib/parse/LibParseChar.sol` |
| `CMASK_NUMERIC_0_9` | `rain.string/lib/parse/LibParseCMask.sol` |
| `CMASK_NEGATIVE_SIGN` | `rain.string/lib/parse/LibParseCMask.sol` |
| `CMASK_E_NOTATION` | `rain.string/lib/parse/LibParseCMask.sol` |
| `CMASK_ZERO` | `rain.string/lib/parse/LibParseCMask.sol` |
| `CMASK_DECIMAL_POINT` | `rain.string/lib/parse/LibParseCMask.sol` |
| `LibParseDecimal` | `rain.string/lib/parse/LibParseDecimal.sol` |
| `MalformedExponentDigits` | `../../error/ErrParse.sol` |
| `ParseDecimalPrecisionLoss` | `../../error/ErrParse.sol` |
| `MalformedDecimalPoint` | `../../error/ErrParse.sol` |
| `ParseDecimalFloatExcessCharacters` | `../../error/ErrParse.sol` |
| `ParseEmptyDecimalString` | `rain.string/error/ErrParse.sol` |
| `LibDecimalFloat`, `Float` | `../LibDecimalFloat.sol` |

### Architecture Summary

`parseDecimalFloatInline` is the core parser operating on raw memory pointers `[start, end)`. It parses, in order: an optional negative sign, integer digits, an optional decimal point followed by fractional digits (with trailing zero stripping), and an optional `e`/`E` followed by a signed exponent. It returns an error-selector pattern (`bytes4(0)` = success) rather than reverting.

`parseDecimalFloat` is a high-level wrapper that extracts memory pointers from a `string memory`, calls the inline parser, checks that the entire string was consumed, and packs the result into a `Float` via `LibDecimalFloat.packLossy`.

### Detailed Walkthrough

**Lines 39-56 (sign and integer part):**
- `skipMask` advances past all characters matching `CMASK_NEGATIVE_SIGN` (line 41). Multiple dashes are consumed but are later caught as an error by `unsafeDecimalStringToSignedInt` which only handles one sign character.
- `skipMask` for `CMASK_NUMERIC_0_9` identifies the integer digit span (line 45). If no digits found, returns `ParseEmptyDecimalString` (line 47).
- `unsafeDecimalStringToSignedInt(start, cursor)` parses the full range from original `start` (including the sign character) through the end of digits (line 51). This function delegates to `unsafeDecimalStringToInt` which performs overflow detection up to uint256 range, and `unsafeDecimalStringToSignedInt` checks int256 range.

**Lines 58-126 (fractional part):**
- `isMask` checks for decimal point at cursor (line 58). If found, cursor advances past it (line 61).
- `skipMask` identifies fractional digits (line 63). If no digits after the point, returns `MalformedDecimalPoint` (line 65).
- Trailing zero stripping loop (line 70): walks backwards from `cursor` via `isMask(nonZeroCursor - 1, end, CMASK_ZERO)`. Relies on the decimal point character at `fracStart - 1` to act as a natural lower bound (`.` is not in `CMASK_ZERO`).
- If non-zero fractional digits exist, they are parsed via `unsafeDecimalStringToSignedInt(fracStart, nonZeroCursor)` (line 76). A negative fracValue is rejected (line 83-84) since the sign is inherited from the integer part (line 86-88).
- Exponent is set to `int256(fracStart) - int256(nonZeroCursor)` (line 96), always non-positive.
- When `signedCoefficient != 0`, the integer value is rescaled by `10^(-exponent)` and combined with fracValue (lines 104-125). Overflow is checked via division round-trip (line 117) and int224 truncation (line 120). The `scale > 67` guard (line 108) prevents exponentiation overflow since `10^67 < 2^224`.

**Lines 128-151 (e-notation exponent):**
- `isMask` checks for `e`/`E` (line 128). If found, parses optional sign + digits.
- `skipMask` for `CMASK_NEGATIVE_SIGN` allows multiple dashes (line 132), but `unsafeDecimalStringToSignedInt` only handles one, so extra dashes produce an error.
- The parsed e-value is added to the existing exponent (line 150) inside `unchecked`. This is the location of the sole LOW finding.

**Lines 153-157 (zero normalization):**
- If the final coefficient is zero, the exponent is forced to zero. This prevents distinct zero representations.

**Lines 169-196 (`parseDecimalFloat` wrapper):**
- Assembly block (line 172-175) extracts `start` and `end` pointers from string memory layout.
- Checks that the entire string was consumed (line 179); if not, returns `ParseDecimalFloatExcessCharacters`.
- `packLossy` packs the result into `Float`; if lossy, returns `ParseDecimalPrecisionLoss` (line 183).

### Edge Cases Verified

| Input | Behavior | Lines |
|---|---|---|
| Empty string `""` | `ParseEmptyDecimalString` | 46-47 |
| Non-numeric `"hello"` | `ParseEmptyDecimalString` | 46-47 |
| Leading `.` without integer `".1"` | `ParseEmptyDecimalString` | 46-47 |
| Trailing `.` without fraction `"1."` | `MalformedDecimalPoint` | 64-65 |
| `"e1"` (e without leading digits) | `ParseEmptyDecimalString` | 46-47 |
| `"1e"` (e without trailing digits) | `MalformedExponentDigits` | 136-137 |
| `"1e-"` (e with sign but no digits) | `MalformedExponentDigits` | 136-137 |
| `"-0"` | Coefficient 0, exponent 0 (no negative zero) | 153-157 |
| `"---123"` (multiple signs) | `ParseDecimalOverflow` from downstream | 51 |
| `"1e--5"` (multiple e-signs) | `ParseDecimalOverflow` from downstream | 143 |
| `"0.000"` (all-zero fraction) | `nonZeroCursor == fracStart`, fracValue stays 0 | 70-74 |
| Leading zeros `"0001"` | Parsed correctly as 1 | 45, 51 |
| Trailing zeros in fraction `"1.10"` | Stripped; `"1.10"` -> coeff=11, exp=-1 | 69-72 |
| `start > end` | `ParseEmptyDecimalString` (skipMask no-ops) | 45-47 |
| Very long fractional part with nonzero integer | `ParseDecimalPrecisionLoss` if > 67 fractional digits | 108-109 |
| `int256.max` coefficient + `int256.max` exponent | Parsed correctly; tested in test suite | N/A |
| `int256.min` coefficient + `int256.min` exponent | Parsed correctly; tested in test suite | N/A |

---

## Findings

---

### A10-1: Unchecked `exponent += eValue` can silently wrap on int256 overflow (LOW)

**Location:** Line 150, inside `unchecked {}` block

**Description:**

On line 150, the exponent from the fractional part is added to the e-notation exponent value:

```solidity
exponent += eValue;
```

Both `exponent` and `eValue` are `int256`. This addition is inside an `unchecked` block, so int256 overflow wraps silently. When the input has both a fractional part and an e-notation exponent, their sum can overflow.

Concrete scenario: parsing a string like `"0.<many zeros>1e<int256.max>"` produces a large negative `exponent` from the fractional part and `eValue = int256.max`. Their unchecked sum wraps to a positive number. The function returns `signedCoefficient = 1` with a wrapped (semantically incorrect) positive exponent.

For the wrapping to occur, the fractional exponent must be sufficiently negative. When the integer part is nonzero, the `scale > 67` guard (line 108) caps the fractional exponent at -67, and `-67 + int256.max` does not overflow. The issue only arises when `signedCoefficient == 0` (integer part is zero), in which case there is no scale guard and the fractional exponent is unbounded (derived from pointer arithmetic on line 96). In that path, the fractional exponent can be as negative as the number of fractional digits allows.

**Impact:**

LOW. The `parseDecimalFloat` wrapper mitigates this because `packLossy` checks that the exponent fits in int32 and will either revert with `ExponentOverflow` or return `lossless = false`. However, callers of `parseDecimalFloatInline` directly receive the wrapped value with no indication of overflow. Since `parseDecimalFloatInline` is `internal`, only code within the same contract (or contracts inheriting/importing the library) can call it.

Practical exploitability is further constrained by the fact that constructing a string with enough fractional zeros to push the exponent toward `int256.min` requires enormous memory allocation and corresponding gas. The code comments on lines 92-94 acknowledge this: "technically these numbers could be out of range but in the intended use case that would imply a memory region that is physically impossible to exist."

**Recommendation:**

Add an overflow check after line 150, or document the invariant that `parseDecimalFloatInline` callers must validate the returned exponent fits their target range. See `.fixes/A10-1.md`.

---

### A10-2: `rescaledIntValue + fracValue` sum not rechecked against int224 (INFORMATIONAL)

**Location:** Line 124

**Description:**

After the int224 truncation check on `rescaledIntValue` (line 120), the fractional value is added without rechecking:

```solidity
signedCoefficient = rescaledIntValue + fracValue;
```

`rescaledIntValue` is verified to fit in int224 (line 120). `fracValue` is at most ~67 decimal digits (bounded by `scale > 67`), which also fits in int224 (int224 max is approximately 2.69e67). However, their sum can exceed int224 range by up to a factor of 2.

**Impact:**

INFORMATIONAL. No int256 overflow is possible since both operands fit in int224, so their sum fits in at most ~int225, well within int256. The `parseDecimalFloat` wrapper catches any int224 overflow via `packLossy` which returns `lossless = false`. The `parseDecimalFloatInline` return value accurately represents the mathematical result. The behavior is correct; this note exists only to document that the returned `signedCoefficient` may slightly exceed int224 range.

---

### A10-3: Multiple consecutive negative signs consumed by `skipMask` but rejected downstream with misleading error (INFORMATIONAL)

**Location:** Lines 41, 132

**Description:**

`skipMask(cursor, end, CMASK_NEGATIVE_SIGN)` on line 41 advances past ALL consecutive dash characters, not just one. For input like `"---123"`, all three dashes are consumed. Then `unsafeDecimalStringToSignedInt(start, cursor)` on line 51 parses the full span `"---123"`. It detects one `-`, then passes `"--123"` to `unsafeDecimalStringToInt`, which interprets `'-'` (ASCII 0x2D) as a digit by subtracting the `'0'` offset (ASCII 0x30). In unchecked assembly this underflows to a large value, which triggers `ParseDecimalOverflow`.

The same pattern applies to line 132 for the exponent sign: `"1e---5"` produces `ParseDecimalOverflow`.

**Impact:**

INFORMATIONAL. The input is always rejected, which is correct. The error selector (`ParseDecimalOverflow`) is misleading for what is really a malformed-sign condition, but this is a usability/diagnostics concern, not a security issue.

---

### A10-4: Assembly block in `parseDecimalFloat` not annotated as `"memory-safe"` (INFORMATIONAL)

**Location:** Line 172

**Description:**

The assembly block at line 172:

```solidity
assembly {
    start := add(str, 0x20)
    end := add(start, mload(str))
}
```

This block only reads from memory (no `mstore`, no free-memory-pointer modification). It qualifies for the `"memory-safe"` annotation. Other assembly blocks in the dependency chain (e.g., in `LibParseChar.skipMask`, `LibParseChar.isMask`, `LibDecimalFloat.packLossy`) are annotated as `"memory-safe"`.

**Impact:**

INFORMATIONAL. The missing annotation prevents the Solidity optimizer from making certain assumptions around this block, marginally reducing optimization potential. No correctness or security impact.

---

### A10-5: Trailing zero stripping loop relies on implicit lower bound from decimal point character (INFORMATIONAL)

**Location:** Line 70

**Description:**

The trailing zero stripping loop:

```solidity
uint256 nonZeroCursor = cursor;
while (LibParseChar.isMask(nonZeroCursor - 1, end, CMASK_ZERO) == 1) {
    nonZeroCursor--;
}
```

This walks backwards through memory. `isMask` only checks an upper bound (`lt(cursor, end)`), not a lower bound. The loop terminates because the byte at `fracStart - 1` is always the decimal point character `'.'`, which does not match `CMASK_ZERO`.

The implicit invariant chain:
1. We entered this block because `isMask(cursor, end, CMASK_DECIMAL_POINT) == 1` (line 58).
2. `cursor++` at line 61 means `fracStart = cursor` and `fracStart - 1` points to `'.'`.
3. `'.'` (ASCII 0x2E) is not in `CMASK_ZERO` (which matches only `'0'`, ASCII 0x30).
4. Therefore the loop cannot decrement `nonZeroCursor` below `fracStart`.

**Impact:**

INFORMATIONAL. The logic is correct. The implicit bound through character identity rather than an explicit `nonZeroCursor > fracStart` guard makes the code slightly fragile in the face of hypothetical refactoring (e.g., if `CMASK_ZERO` were ever broadened or the decimal point were consumed differently). No current security issue.

---

## Summary

| ID | Severity | Title |
|---|---|---|
| A10-1 | LOW | Unchecked `exponent += eValue` can silently wrap on int256 overflow |
| A10-2 | INFORMATIONAL | `rescaledIntValue + fracValue` sum not rechecked against int224 |
| A10-3 | INFORMATIONAL | Multiple negative signs consumed then rejected with misleading error |
| A10-4 | INFORMATIONAL | Assembly block not annotated as `"memory-safe"` |
| A10-5 | INFORMATIONAL | Trailing zero stripping loop relies on implicit lower bound |

Overall, `LibParseDecimalFloat.sol` is well-structured with thorough input validation. All invalid inputs produce error selectors rather than reverting with string messages (the sole hard revert in the dependency `LibParseDecimal.unsafeDecimalStringToInt` for `start == 0` is a true programming error guard). The `parseDecimalFloat` wrapper provides a robust safety net via `packLossy` validation. The single LOW finding (A10-1) has minimal practical impact due to physical memory constraints and the mitigation provided by the wrapper function.
