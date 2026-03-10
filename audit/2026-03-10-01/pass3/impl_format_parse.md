# Pass 3 -- Documentation Audit: Implementation, Format, Parse

**Agents:** A08 (format), A09 (implementation), A10 (parse)
**Date:** 2026-03-10

---

## Evidence of Thorough Reading

### A08: `src/lib/format/LibFormatDecimalFloat.sol` (165 lines)

**Library:** `LibFormatDecimalFloat`

| # | Function | Line | Visibility |
|---|----------|------|------------|
| 1 | `countSigFigs` | 18 | `internal pure` |
| 2 | `toDecimalString` | 58 | `internal pure` |

### A09: `src/lib/implementation/LibDecimalFloatImplementation.sol` (1307 lines)

**Library:** `LibDecimalFloatImplementation`

| # | Function | Line | Visibility |
|---|----------|------|------------|
| 1 | `minus` | 71 | `internal pure` |
| 2 | `absUnsignedSignedCoefficient` | 89 | `internal pure` |
| 3 | `unabsUnsignedMulOrDivLossy` | 116 | `internal pure` |
| 4 | `mul` | 160 | `internal pure` |
| 5 | `div` | 272 | `internal pure` |
| 6 | `mul512` | 466 | `internal pure` |
| 7 | `mulDiv` | 479 | `internal pure` |
| 8 | `add` | 610 | `internal pure` |
| 9 | `sub` | 703 | `internal pure` |
| 10 | `eq` | 724 | `internal pure` |
| 11 | `inv` | 736 | `internal pure` |
| 12 | `lookupLogTableVal` | 744 | `internal view` |
| 13 | `log10` | 783 | `internal view` |
| 14 | `pow10` | 902 | `internal view` |
| 15 | `maximize` | 957 | `internal pure` |
| 16 | `maximizeFull` | 1011 | `internal pure` |
| 17 | `compareRescale` | 1047 | `internal pure` |
| 18 | `withTargetExponent` | 1127 | `internal pure` |
| 19 | `intFrac` | 1169 | `internal pure` |
| 20 | `mantissa4` | 1197 | `internal pure` |
| 21 | `lookupAntilogTableY1Y2` | 1227 | `internal view` |
| 22 | `unitLinearInterpolation` | 1267 | `internal pure` |

(Also: `lookupTableVal` at line 1239 is an inline assembly `function`, not a Solidity function.)

### A10: `src/lib/parse/LibParseDecimalFloat.sol` (197 lines)

**Library:** `LibParseDecimalFloat`

| # | Function | Line | Visibility |
|---|----------|------|------------|
| 1 | `parseDecimalFloatInline` | 34 | `internal pure` |
| 2 | `parseDecimalFloat` | 169 | `internal pure` |

---

## NatSpec Audit: Function-by-Function

### A08: LibFormatDecimalFloat

#### `countSigFigs` (line 18)

- **Has NatSpec:** Yes (line 14-17).
- **`@notice`/summary:** Plain `///` summary: "Counts the number of significant figures in a decimal float." Adequate.
- **`@param signedCoefficient`:** Documented. Accurate.
- **`@param exponent`:** Documented. Accurate.
- **`@return sigFigs`:** Documented: "The number of significant figures." Named return `sigFigs` matches.
- **Issues:** None.

#### `toDecimalString` (line 58)

- **Has NatSpec:** Yes (lines 52-56).
- **`@notice`/summary:** "Format a decimal float as a string." Adequate.
- **`@param float`:** Documented: "The decimal float to format."
- **`@param scientific`:** NOT documented. Missing `@param scientific`.
- **`@return`:** Documented: "The string representation of the decimal float." Return is unnamed in signature, which is consistent.
- **Issues:** See **A08-1** below.

### A09: LibDecimalFloatImplementation

#### `minus` (line 71)

- **Has NatSpec:** Yes (lines 53-70).
- **`@notice`/summary:** Plain `///` summary: "Negates a float. Equivalent to `0 - x`." Plus reference to the spec. Thorough.
- **`@param signedCoefficient`:** Documented (line 66-67). Accurate.
- **`@param exponent`:** Documented (line 68). Accurate.
- **`@return` (2 returns):** Documented as `@return signedCoefficient` (line 69) and `@return exponent` (line 70). However, the actual function signature has **unnamed** returns: `returns (int256, int256)`. Solidity NatSpec matches return tags positionally, so this is technically fine but using named tags for unnamed returns is a mild inconsistency. INFORMATIONAL.
- **Issues:** None actionable.

#### `absUnsignedSignedCoefficient` (line 89)

- **Has NatSpec:** Yes (lines 85-88).
- **Summary:** "Returns the absolute value of a signed coefficient as an unsigned integer."
- **`@param signedCoefficient`:** Documented.
- **`@return`:** Documented: "The absolute value as an unsigned integer."
- **Issues:** None.

#### `unabsUnsignedMulOrDivLossy` (line 116)

- **Has NatSpec:** Yes (lines 107-115).
- **Summary:** "Given the absolute value of the result coefficient, and the signs of the input coefficients, returns the signed coefficient and exponent of the result of a multiplication or division operation."
- **`@param a`:** Documented: "The signed coefficient of the first operand."
- **`@param b`:** Documented: "The signed coefficient of the second operand."
- **`@param signedCoefficientAbs`:** Documented: "The absolute value of the result coefficient."
- **`@param exponent`:** Documented: "The exponent of the result."
- **`@return signedCoefficient`:** Documented.
- **`@return exponent`:** Documented.
- **Issues:** None.

#### `mul` (line 160)

- **Has NatSpec:** Yes (lines 153-159).
- **Summary:** "Stack only implementation of `mul`."
- **`@param signedCoefficientA`, `@param exponentA`, `@param signedCoefficientB`, `@param exponentB`:** All documented.
- **`@return signedCoefficient`, `@return exponent`:** Both documented.
- **Issues:** None.

#### `div` (line 272)

- **Has NatSpec:** Yes (lines 221-271). Extensive specification comment referencing the decimal standard.
- **`@param`/`@return`:** MISSING. The function has four parameters (`signedCoefficientA`, `exponentA`, `signedCoefficientB`, `exponentB`) and two returns, but there are NO `@param` or `@return` tags. Only the specification quote is present.
- **Issues:** See **A09-1** below.

#### `mul512` (line 466)

- **Has NatSpec:** Partial (lines 463-465).
- **Summary:** "mul512 from Open Zeppelin. Simply part of the original mulDiv function abstracted out for reuse elsewhere."
- **`@param a`:** NOT documented.
- **`@param b`:** NOT documented.
- **`@return high`:** NOT documented.
- **`@return low`:** NOT documented.
- **Issues:** See **A09-2** below.

#### `mulDiv` (line 479)

- **Has NatSpec:** Partial (lines 477-478).
- **Summary:** "mulDiv as seen in Open Zeppelin, PRB Math, Solady, and other libraries."
- **`@param x`:** NOT documented.
- **`@param y`:** NOT documented.
- **`@param denominator`:** NOT documented.
- **`@return result`:** NOT documented.
- **Issues:** See **A09-3** below.

#### `add` (line 610)

- **Has NatSpec:** Yes (lines 557-609). Extensive specification comment and full `@param`/`@return` tags.
- **`@param signedCoefficientA`, `@param exponentA`, `@param signedCoefficientB`, `@param exponentB`:** All documented.
- **`@return signedCoefficient`, `@return exponent`:** Both documented.
- **Issues:** None.

#### `sub` (line 703)

- **Has NatSpec:** Partial (lines 695-702).
- **`@param`:** All four params documented.
- **`@return signedCoefficient`, `@return exponent`:** Both documented.
- **Summary/`@notice`:** MISSING. There is no description of what the function does. The `@param`/`@return` tags are present but there is no summary line or `@notice` explaining this is subtraction.
- **Issues:** See **A09-4** below.

#### `eq` (line 724)

- **Has NatSpec:** Yes (lines 712-723).
- **Summary:** "Numeric equality for floats."
- **`@param`:** All four params documented.
- **`@return`:** Documented: "`true` if the two floats are equal, `false` otherwise."
- **Issues:** None.

#### `inv` (line 736)

- **Has NatSpec:** Minimal (line 735).
- **Summary:** "Inverts a float. Equivalent to `1 / x`."
- **`@param signedCoefficient`:** NOT documented.
- **`@param exponent`:** NOT documented.
- **`@return` (2 returns):** NOT documented.
- **Issues:** See **A09-5** below.

#### `lookupLogTableVal` (line 744)

- **Has NatSpec:** Yes (lines 740-743).
- **Summary:** "Looks up the log10 table value for a given index."
- **`@param tables`:** Documented: "The address of the log tables data contract."
- **`@param index`:** Documented: "The index into the log table."
- **`@return result`:** Documented: "The log10 table value."
- **Issues:** None.

#### `log10` (line 783)

- **Has NatSpec:** Yes (lines 772-782).
- **Summary:** "log10(x) for a float x."
- **`@param signedCoefficient`:** Documented.
- **`@param exponent`:** Documented.
- **`@return signedCoefficient`, `@return exponent`:** Both documented.
- **Missing param:** The first parameter `tablesDataContract` (address) is NOT documented with `@param`.
- **Issues:** See **A09-6** below.

#### `pow10` (line 902)

- **Has NatSpec:** Yes (lines 891-901).
- **Summary:** "10^x for a float x."
- **`@param signedCoefficient`:** Documented.
- **`@param exponent`:** Documented.
- **`@return signedCoefficient`, `@return exponent`:** Both documented.
- **Missing param:** The first parameter `tablesDataContract` (address) is NOT documented with `@param`.
- **Issues:** See **A09-7** below.

#### `maximize` (line 957)

- **Has NatSpec:** Yes (lines 949-956).
- **Summary:** "Maximizes a float's signed coefficient..."
- **`@param`:** MISSING. No `@param` tags for `signedCoefficient` or `exponent`.
- **`@return signedCoefficient`:** Documented.
- **`@return exponent`:** Documented.
- **`@return full`:** Documented.
- **Issues:** See **A09-8** below.

#### `maximizeFull` (line 1011)

- **Has NatSpec:** Yes (lines 1005-1010).
- **Summary:** "Maximizes a float as per `maximize` but errors if not fully maximized."
- **`@param signedCoefficient`:** Documented.
- **`@param exponent`:** Documented.
- **`@return signedCoefficient`:** Documented.
- **`@return exponent`:** Documented.
- **Issues:** None.

#### `compareRescale` (line 1047)

- **Has NatSpec:** Yes (lines 1019-1046).
- **Summary:** "Rescale two floats so that they are possible to directly compare..."
- **`@param`:** MISSING. No `@param` tags despite having four parameters.
- **`@return`:** MISSING. No `@return` tags despite having two returns.
- **Issues:** See **A09-9** below.

#### `withTargetExponent` (line 1127)

- **Has NatSpec:** Yes (lines 1121-1126).
- **Summary:** "Sets the coefficient so that exponent is the target exponent."
- **`@param signedCoefficient`:** Documented.
- **`@param exponent`:** Documented.
- **`@param targetExponent`:** Documented.
- **`@return`:** Documented: "The new signed coefficient."
- **Issues:** None.

#### `intFrac` (line 1169)

- **Has NatSpec:** Yes (lines 1160-1168).
- **Summary:** "Returns the integer and fractional parts of a float."
- **`@param signedCoefficient`:** Documented.
- **`@param exponent`:** Documented.
- **`@return integer`:** Documented.
- **`@return frac`:** Documented.
- **Issues:** None.

#### `mantissa4` (line 1197)

- **Has NatSpec:** Yes (lines 1191-1196).
- **Summary:** "First 4 digits of the mantissa and whether we need to interpolate."
- **`@param signedCoefficient`:** Documented.
- **`@param exponent`:** Documented.
- **`@return mantissa`:** Documented.
- **`@return interpolate`:** Documented.
- **`@return scale`:** Documented.
- **Issues:** None.

#### `lookupAntilogTableY1Y2` (line 1227)

- **Has NatSpec:** Yes (lines 1219-1225).
- **Summary:** "Looks up the antilog table values y1 and y2 for a given index."
- **`@param tablesDataContract`:** Documented.
- **`@param idx`:** Documented.
- **`@param lossyIdx`:** Documented.
- **`@return y1Coefficient`:** Documented.
- **`@return y2Coefficient`:** Documented.
- **Issues:** None.

#### `unitLinearInterpolation` (line 1267)

- **Has NatSpec:** Yes (lines 1256-1266).
- **Summary:** "Linear interpolation." Plus formula.
- **`@param x1Coefficient`:** Documented.
- **`@param xCoefficient`:** Documented.
- **`@param x2Coefficient`:** Documented.
- **`@param xExponent`:** Documented.
- **`@param y1Coefficient`:** Documented.
- **`@param y2Coefficient`:** Documented.
- **`@param yExponent`:** Documented.
- **`@return signedCoefficient`:** Documented.
- **`@return exponent`:** Documented.
- **Issues:** None.

### A10: LibParseDecimalFloat

#### `parseDecimalFloatInline` (line 34)

- **Has NatSpec:** Yes (lines 25-33).
- **`@notice`:** "Parses a decimal float from a substring defined by [start, end)."
- **`@param start`:** Documented: "The starting index of the substring (inclusive)."
- **`@param end`:** Documented: "The ending index of the substring (exclusive)."
- **`@return errorSelector`:** Documented.
- **`@return cursor`:** Documented.
- **`@return signedCoefficient`:** Documented.
- **`@return exponent`:** Documented.
- **Issues:** None.

#### `parseDecimalFloat` (line 169)

- **Has NatSpec:** Yes (lines 161-168).
- **`@notice`:** "Parses a decimal float from a string."
- **`@param str`:** Documented.
- **`@return errorSelector`:** NOT documented. The function returns `(bytes4, Float)` but the NatSpec at line 166-167 says `@return errorSelector The error selector...`. This is documented.
- **`@return result`:** Documented at line 168.
- **Issues:** The return names in the NatSpec (`errorSelector`, `result`) do not match the unnamed returns in the signature `returns (bytes4, Float)`. Positional matching applies, so this is technically correct but slightly misleading since there are no named returns in the signature. INFORMATIONAL.

---

## Findings

### A08-1: `toDecimalString` missing `@param scientific` documentation

**Severity:** LOW
**File:** `src/lib/format/LibFormatDecimalFloat.sol`, line 58
**Status:** Open

The `toDecimalString` function accepts a `bool scientific` parameter that controls whether the output uses scientific notation (e.g., `1.23e45`) or plain decimal format. This parameter is undocumented in NatSpec. Given the significant behavior change it controls (including triggering `UnformatableExponent` revert vs. `maximizeFull` + exponent display), the parameter deserves documentation.

### A09-1: `div` missing all `@param` and `@return` NatSpec tags

**Severity:** LOW
**File:** `src/lib/implementation/LibDecimalFloatImplementation.sol`, line 272
**Status:** Open

The `div` function has a lengthy specification quotation (lines 221-270) but no `@param` or `@return` NatSpec tags for its four parameters and two return values. Every other arithmetic function in the library (`mul`, `add`, `sub`) documents these. The `div` function is a core public API of the library and should be documented consistently.

### A09-2: `mul512` missing all `@param` and `@return` NatSpec tags

**Severity:** INFORMATIONAL
**File:** `src/lib/implementation/LibDecimalFloatImplementation.sol`, line 466
**Status:** Open

`mul512` has a brief summary but no `@param` or `@return` documentation. Parameters `a` and `b` and named returns `high` and `low` are undocumented.

### A09-3: `mulDiv` missing all `@param` and `@return` NatSpec tags

**Severity:** INFORMATIONAL
**File:** `src/lib/implementation/LibDecimalFloatImplementation.sol`, line 479
**Status:** Open

`mulDiv` has a brief summary and credit line but no `@param` or `@return` documentation. Parameters `x`, `y`, `denominator` and named return `result` are undocumented.

### A09-4: `sub` missing summary/description

**Severity:** INFORMATIONAL
**File:** `src/lib/implementation/LibDecimalFloatImplementation.sol`, line 703
**Status:** Open

`sub` has `@param` and `@return` tags but no summary line explaining that this function performs subtraction. All other arithmetic functions (`add`, `mul`, `div`, `minus`) have summaries.

### A09-5: `inv` missing `@param` and `@return` NatSpec tags

**Severity:** LOW
**File:** `src/lib/implementation/LibDecimalFloatImplementation.sol`, line 736
**Status:** Open

`inv` has a one-line summary but no `@param` or `@return` documentation. The function takes two parameters (`signedCoefficient`, `exponent`) and returns two values, all undocumented.

### A09-6: `log10` missing `@param tablesDataContract`

**Severity:** INFORMATIONAL
**File:** `src/lib/implementation/LibDecimalFloatImplementation.sol`, line 783
**Status:** Open

The `log10` function documents `@param signedCoefficient` and `@param exponent` but omits `@param tablesDataContract`, its first parameter. This creates a positional mismatch: the first `@param` tag describes the second actual parameter. Solidity NatSpec processors may misattribute the documentation.

### A09-7: `pow10` missing `@param tablesDataContract`

**Severity:** INFORMATIONAL
**File:** `src/lib/implementation/LibDecimalFloatImplementation.sol`, line 902
**Status:** Open

Same issue as A09-6. The `pow10` function documents `@param signedCoefficient` and `@param exponent` but omits `@param tablesDataContract`.

### A09-8: `maximize` missing `@param` tags

**Severity:** INFORMATIONAL
**File:** `src/lib/implementation/LibDecimalFloatImplementation.sol`, line 957
**Status:** Open

`maximize` has `@return` tags but no `@param` tags for `signedCoefficient` and `exponent`. The sibling function `maximizeFull` (line 1011) correctly documents both `@param` and `@return`.

### A09-9: `compareRescale` missing `@param` and `@return` tags

**Severity:** LOW
**File:** `src/lib/implementation/LibDecimalFloatImplementation.sol`, line 1047
**Status:** Open

`compareRescale` has a thorough summary and specification reference (lines 1019-1046) but no `@param` or `@return` NatSpec tags. It takes four parameters and returns two values, all undocumented. This function is used by `eq` and is part of the comparison API.

---

## Summary

| ID | Severity | File | Issue |
|----|----------|------|-------|
| A08-1 | LOW | LibFormatDecimalFloat.sol:58 | `toDecimalString` missing `@param scientific` |
| A09-1 | LOW | LibDecimalFloatImplementation.sol:272 | `div` missing all `@param`/`@return` |
| A09-2 | INFO | LibDecimalFloatImplementation.sol:466 | `mul512` missing all `@param`/`@return` |
| A09-3 | INFO | LibDecimalFloatImplementation.sol:479 | `mulDiv` missing all `@param`/`@return` |
| A09-4 | INFO | LibDecimalFloatImplementation.sol:703 | `sub` missing summary description |
| A09-5 | LOW | LibDecimalFloatImplementation.sol:736 | `inv` missing `@param`/`@return` |
| A09-6 | INFO | LibDecimalFloatImplementation.sol:783 | `log10` missing `@param tablesDataContract` |
| A09-7 | INFO | LibDecimalFloatImplementation.sol:902 | `pow10` missing `@param tablesDataContract` |
| A09-8 | INFO | LibDecimalFloatImplementation.sol:957 | `maximize` missing `@param` tags |
| A09-9 | LOW | LibDecimalFloatImplementation.sol:1047 | `compareRescale` missing `@param`/`@return` |

**LOW findings:** 4 (A08-1, A09-1, A09-5, A09-9)
**INFORMATIONAL findings:** 6 (A09-2, A09-3, A09-4, A09-6, A09-7, A09-8)
