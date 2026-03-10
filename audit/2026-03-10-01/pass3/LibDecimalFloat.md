# Audit Pass 3 -- Documentation: `src/lib/LibDecimalFloat.sol`

**Auditor agent:** A06
**Date:** 2026-03-10
**Library:** `LibDecimalFloat` (line 44, `src/lib/LibDecimalFloat.sol`)

---

## Evidence of reading

Source file: `src/lib/LibDecimalFloat.sol` (796 lines total)

### Type declaration

| Item | Line |
|---|---|
| `type Float is bytes32` | 16 |

### Library-level NatSpec (lines 18-43)

`@title LibDecimalFloat` is present. The description covers: decimal floating point, 224-bit signed coefficient, 32-bit signed exponent, no NaN/Infinity/negative-zero, revert-on-nonsense design, decimal-not-binary rationale with precision discussion.

### Constants (lines 47-92)

| Constant | Line | Has NatSpec? |
|---|---|---|
| `LOG_TABLES_ADDRESS` | 50 | Yes |
| `FLOAT_ZERO` | 53 | Yes |
| `FLOAT_ONE` | 56 | Yes |
| `FLOAT_HALF` | 60 | Yes |
| `FLOAT_TWO` | 64 | Yes |
| `FLOAT_MAX_POSITIVE_VALUE` | 68 | Yes |
| `FLOAT_MIN_POSITIVE_VALUE` | 74 | Yes |
| `FLOAT_MAX_NEGATIVE_VALUE` | 80 | Yes |
| `FLOAT_MIN_NEGATIVE_VALUE` | 86 | Yes |
| `FLOAT_E` | 91 | Yes |

### Functions (lines 104-795)

| # | Function | Line | `@param` | `@return` | Notes |
|---|---|---|---|---|---|
| 1 | `fromFixedDecimalLossy(uint256,uint8)` | 104 | Yes (2/2) | Yes (3/3) | Complete |
| 2 | `fromFixedDecimalLossyPacked(uint256,uint8)` | 132 | Yes (2/2) | Yes (2/2) | Complete |
| 3 | `fromFixedDecimalLossless(uint256,uint8)` | 144 | Yes (2/2) | Yes (2/2) | Complete |
| 4 | `fromFixedDecimalLosslessPacked(uint256,uint8)` | 158 | Yes (2/2) | Yes (1/1) | **Stale reference** -- see A06-6 |
| 5 | `toFixedDecimalLossy(int256,int256,uint8)` | 176 | Yes (3/3) | Yes (2/2) | Complete |
| 6 | `toFixedDecimalLossy(Float,uint8)` | 254 | Yes (2/2) | Yes (2/2) | Complete |
| 7 | `toFixedDecimalLossless(int256,int256,uint8)` | 265 | Yes (3/3) | Yes (1/1) | Complete |
| 8 | `toFixedDecimalLossless(Float,uint8)` | 286 | Yes (2/2) | Yes (1/1) | Complete |
| 9 | `packLossy(int256,int256)` | 299 | Yes (2/2) | Partial (1/2) | **Missing** `@return lossless` -- see A06-7; **Stale type name** `PackedFloat` -- see A06-8 |
| 10 | `packLossless(int256,int256)` | 358 | Yes (2/2) | Yes (1/1) | Complete |
| 11 | `unpack(Float)` | 373 | Yes (1/1) | Yes (2/2) | **Stale reference** "inverse of `pack`" -- see A06-9 |
| 12 | `add(Float,Float)` | 388 | Yes (2/2) | **Missing** | Missing `@return`; misleading "Same as add" -- see A06-10 |
| 13 | `sub(Float,Float)` | 405 | Yes (2/2) | **Missing** | **Incorrect description** "Subtract float a from float b" is semantically backwards -- see A06-11 |
| 14 | `minus(Float)` | 421 | Yes (1/1) | **Missing** | Misleading "Same as minus" -- see A06-10 |
| 15 | `abs(Float)` | 440 | Yes (1/1) | **Missing** | |
| 16 | `mul(Float,Float)` | 474 | Yes (2/2) | **Missing** | |
| 17 | `div(Float,Float)` | 491 | Yes (2/2) | **Missing** | "Same as divide" references non-existent name -- see A06-12 |
| 18 | `inv(Float)` | 507 | Yes (1/1) | **Missing** | Misleading "Same as inv" -- see A06-10 |
| 19 | `eq(Float,Float)` | 520 | Yes (2/2) | **Missing** | Misleading "Same as eq" -- see A06-10 |
| 20 | `lt(Float,Float)` | 531 | Yes (2/2) | **Missing** | |
| 21 | `gt(Float,Float)` | 545 | Yes (2/2) | **Missing** | |
| 22 | `lte(Float,Float)` | 557 | **Missing** | **Missing** | No `@param` or `@return` tags at all |
| 23 | `gte(Float,Float)` | 569 | **Missing** | **Missing** | No `@param` or `@return` tags at all |
| 24 | `integer(Float)` | 582 | Yes (1/1) | Yes (1/1) | Complete |
| 25 | `frac(Float)` | 593 | Yes (1/1) | Yes (1/1) | Complete |
| 26 | `floor(Float)` | 603 | Yes (1/1) | **Missing** | |
| 27 | `ceil(Float)` | 621 | Yes (1/1) | **Missing** | |
| 28 | `pow10(Float,address)` | 652 | Yes (2/2) | **Missing** | "Same as power10" references non-existent name -- see A06-12 |
| 29 | `log10(Float,address)` | 668 | Yes (2/2) | **Missing** | Misleading "Same as log10" -- see A06-10 |
| 30 | `pow(Float,Float,address)` | 690 | Yes (3/3) | **Missing** | |
| 31 | `sqrt(Float,address)` | 764 | Yes (2/2) | **Missing** | |
| 32 | `min(Float,Float)` | 773 | Yes (2/2) | Yes (1/1) | Complete |
| 33 | `max(Float,Float)` | 781 | Yes (2/2) | **Missing** | Inconsistent with `min` which has `@return` |
| 34 | `isZero(Float)` | 788 | Yes (1/1) | **Missing** | |

---

## Findings

### A06-6 `fromFixedDecimalLosslessPacked` NatSpec references non-existent `fromFixedDecimalLossyMem` [LOW]

**File:** `src/lib/LibDecimalFloat.sol` lines 152-155
**Type:** Stale documentation reference

The NatSpec for `fromFixedDecimalLosslessPacked` (line 152) says:
```
/// Lossless version of `fromFixedDecimalLossyMem`. This will revert if the
/// conversion is lossy.
/// @param value As per `fromFixedDecimalLossyMem`.
/// @param decimals As per `fromFixedDecimalLossyMem`.
```

No function named `fromFixedDecimalLossyMem` exists anywhere in the codebase. A grep across all source files returns zero matches outside this NatSpec block. This appears to be a leftover from a previous API design. The function actually delegates to `fromFixedDecimalLossless` (which in turn calls `fromFixedDecimalLossy`), so the correct reference should be `fromFixedDecimalLossyPacked` or `fromFixedDecimalLossy`.

**Impact:** Developers reading the NatSpec to understand the function's behavior will be pointed to a non-existent function, making the documentation misleading.

### A06-7 `packLossy` NatSpec missing `@return lossless` and references non-existent `PackedFloat` type [LOW]

**File:** `src/lib/LibDecimalFloat.sol` lines 291-299
**Type:** Incomplete and stale documentation

The `packLossy` function signature is:
```solidity
function packLossy(int256 signedCoefficient, int256 exponent) internal pure returns (Float float, bool lossless)
```

Two issues:

1. The NatSpec only documents `@return float` (line 297-298) but omits `@return lossless`. The lossless flag is critical for callers to know whether the packing truncated precision. Missing documentation for this return value is a meaningful gap since the entire lossy/lossless distinction is a core design pattern throughout the library.

2. The description at line 291 says "Pack a signed coefficient and exponent into a single `PackedFloat`." The type `PackedFloat` does not exist in the codebase -- the actual type is `Float`. This is a stale reference from an earlier design iteration.

### A06-8 `unpack` NatSpec references non-existent function `pack` [INFO]

**File:** `src/lib/LibDecimalFloat.sol` lines 366-367
**Type:** Stale documentation reference

The NatSpec says:
```
/// Unpack a packed bytes32 into a signed coefficient and exponent. This is
/// the inverse of `pack`.
```

No function named `pack` exists in the library. The packing functions are named `packLossy` and `packLossless`. The doc should reference one or both of these.

**Impact:** Minor. The reader can infer the intent, but it creates a documentation inconsistency.

### A06-9 `sub` NatSpec says "Subtract float a from float b" -- semantically backwards [LOW]

**File:** `src/lib/LibDecimalFloat.sol` line 399
**Type:** Incorrect documentation

The NatSpec states:
```
/// Subtract float a from float b.
```

In English, "subtract A from B" means `B - A`. However, the implementation computes `A - B`: it negates `signedCoefficientB` and adds to `signedCoefficientA`, delegating to `LibDecimalFloatImplementation.sub(A, B)` which performs `add(A, minus(B))`.

The parameter names confirm the intent: `@param a The float to subtract from.` and `@param b The float to subtract.` These descriptions correctly describe `A - B`, contradicting the leading summary line.

**Impact:** The leading summary line would cause a developer reading only the first line to believe the operation is `B - A` when it is actually `A - B`. The `@param` tags are correct, which mitigates the confusion somewhat.

### A06-10 Multiple functions use misleading "Same as X" phrasing referencing internal implementation library [INFO]

**File:** `src/lib/LibDecimalFloat.sol` lines 381, 416, 484, 502, 515, 645, 662
**Type:** Misleading documentation pattern

Seven functions use the pattern "Same as X, but accepts a Float struct instead of separate values":
- `add` (line 381): "Same as add"
- `minus` (line 416): "Same as minus"
- `div` (line 484): "Same as divide"
- `inv` (line 502): "Same as inv"
- `eq` (line 515): "Same as eq"
- `pow10` (line 645): "Same as power10"
- `log10` (line 662): "Same as log10"

In all cases, the "separate values" version is in `LibDecimalFloatImplementation`, not in `LibDecimalFloat`. The phrasing implies there is a sibling overload in the same library accepting `(int256, int256, ...)` parameters, which is not the case. Contrast with `toFixedDecimalLossy` and `toFixedDecimalLossless`, which genuinely have both overloads in the same library and use the same phrasing correctly.

This is informational because a developer can still understand the intent, but it is inconsistent with how the overload pattern is used elsewhere in the same file.

### A06-11 NatSpec references to non-existent function names `divide` and `power10` [LOW]

**File:** `src/lib/LibDecimalFloat.sol` lines 484 and 645
**Type:** Stale documentation references

Line 484: "Same as divide" -- no function `divide` exists. The function is named `div` (in `LibDecimalFloatImplementation`).

Line 645: "Same as power10" -- no function `power10` exists. The function is named `pow10` (in `LibDecimalFloatImplementation`).

These appear to be stale references from when the functions may have had different names.

**Impact:** A developer searching for the referenced function name to understand the underlying behavior will find nothing.

### A06-12 22 of 34 functions missing `@return` NatSpec tags [LOW]

**File:** `src/lib/LibDecimalFloat.sol`
**Type:** Incomplete documentation

The following 22 functions have return values but no `@return` tag:

`add`, `sub`, `minus`, `abs`, `mul`, `div`, `inv`, `eq`, `lt`, `gt`, `lte`, `gte`, `floor`, `ceil`, `pow10`, `log10`, `pow`, `sqrt`, `max`, `isZero`, plus the missing `@return lossless` on `packLossy`.

The library is inconsistent: 12 functions (`fromFixedDecimalLossy`, `fromFixedDecimalLossyPacked`, `fromFixedDecimalLossless`, `fromFixedDecimalLosslessPacked`, `toFixedDecimalLossy` x2, `toFixedDecimalLossless` x2, `packLossy` (partial), `packLossless`, `unpack`, `integer`, `frac`, `min`) do have `@return` documentation, while the majority do not.

**Impact:** Incomplete NatSpec generates incomplete documentation artifacts. Tooling and IDE hover-docs will not show return value descriptions for the majority of the API. For a public library, this degrades the developer experience.

### A06-13 `lte` and `gte` missing all `@param` tags [INFO]

**File:** `src/lib/LibDecimalFloat.sol` lines 553-575
**Type:** Incomplete documentation

`lte` (line 557) and `gte` (line 569) have descriptive NatSpec text but are the only two functions in the entire library with zero `@param` tags. All other functions that accept parameters document them. Contrast with `lt` (line 529-530) and `gt` (line 543-544) which have identical signatures and do include `@param a` and `@param b`.

### A06-14 `Float` type has no NatSpec documentation [INFO]

**File:** `src/lib/LibDecimalFloat.sol` line 16
**Type:** Missing documentation

The user-defined value type `Float` is declared at line 16:
```solidity
type Float is bytes32;
```

There is no NatSpec comment on this declaration. The library-level `@title` block (lines 18-43) describes the encoding in detail, but this is attached to the `library LibDecimalFloat` declaration, not to the `type Float` declaration. A developer navigating to the type definition directly would see no documentation.

The packing layout (224-bit signed coefficient in the low bits, 32-bit signed exponent in the high bits) is documented implicitly by the `pack`/`unpack` functions and constants but never stated explicitly at the type declaration.

---

## Summary

| Severity | Count | IDs |
|---|---|---|
| LOW | 5 | A06-6, A06-7, A06-9, A06-11, A06-12 |
| INFO | 4 | A06-8, A06-10, A06-13, A06-14 |

The library has a solid documentation foundation for the conversion functions (`fromFixedDecimal*`, `toFixedDecimal*`) and packing functions, with complete `@param` and `@return` tags. However, the arithmetic, comparison, and math functions (which constitute the majority of the API) are systematically missing `@return` tags. There are also several stale references to renamed/removed functions (`fromFixedDecimalLossyMem`, `PackedFloat`, `pack`, `divide`, `power10`) and one semantically incorrect description (`sub`).
