# Pass 1 (Security) -- Error Definition Files

Agents: A02, A03, A04
Date: 2026-03-10

---

## A02: `src/error/ErrDecimalFloat.sol`

### Evidence of Thorough Reading

- **File type:** File-level error definitions (no contract/library wrapper)
- **Pragma:** `^0.8.25` (line 3)
- **Import:** `Float` from `../lib/LibDecimalFloat.sol` (line 5)

**Errors defined:**

| Line | Error | Parameters |
|------|-------|------------|
| 8 | `CoefficientOverflow` | `int256 signedCoefficient, int256 exponent` |
| 11 | `ExponentOverflow` | `int256 signedCoefficient, int256 exponent` |
| 15 | `NegativeFixedDecimalConversion` | `int256 signedCoefficient, int256 exponent` |
| 18 | `Log10Zero` | (none) |
| 21 | `Log10Negative` | `int256 signedCoefficient, int256 exponent` |
| 25 | `LossyConversionToFloat` | `int256 signedCoefficient, int256 exponent` |
| 29 | `LossyConversionFromFloat` | `int256 signedCoefficient, int256 exponent` |
| 32 | `ZeroNegativePower` | `Float b` |
| 35 | `MulDivOverflow` | `uint256 x, uint256 y, uint256 denominator` |
| 38 | `MaximizeOverflow` | `int256 signedCoefficient, int256 exponent` |
| 43 | `DivisionByZero` | `int256 signedCoefficient, int256 exponent` |
| 46 | `PowNegativeBase` | `int256 signedCoefficient, int256 exponent` |
| 49 | `WriteError` | (none) |

**No functions, constants, or types defined** (beyond the error declarations).

### Findings

#### A02-1 [INFO] `WriteError` duplicates `rain.datacontract` error and is unused

`WriteError()` at line 49 is an exact duplicate of the error defined in `lib/rain.datacontract/src/error/ErrDataContract.sol:6`. It is imported in `src/lib/deploy/LibDecimalFloatDeploy.sol:17` but never actually used -- there are zero `revert WriteError()` calls anywhere in `src/`. The `rain.datacontract` library defines its own `WriteError` and uses it internally via `LibDataContract.sol`.

This dead error definition adds confusion about which `WriteError` is canonical. It is not exploitable because the selectors are identical (same signature produces the same 4-byte selector), but it is misleading.

#### A02-2 [INFO] `WithTargetExponentOverflow` defined outside error file

The error `WithTargetExponentOverflow(int256, int256, int256)` is defined inline at `src/lib/implementation/LibDecimalFloatImplementation.sol:21` rather than in `ErrDecimalFloat.sol`. This is inconsistent with the project's pattern of centralizing errors in `src/error/`. It is used at lines 1146 and 1153 of the implementation file. Not a security issue but could cause maintenance confusion.

#### A02-3 [INFO] Circular import between `ErrDecimalFloat.sol` and `LibDecimalFloat.sol`

`ErrDecimalFloat.sol` imports `Float` from `LibDecimalFloat.sol` (line 5), and `LibDecimalFloat.sol` imports errors from `ErrDecimalFloat.sol` (lines 5-13). Solidity resolves this correctly for file-level declarations, so this is not a compilation or security issue. However, the circular dependency exists solely to support the `ZeroNegativePower(Float b)` error at line 32. All other errors use primitive types (`int256`, `uint256`). Using `bytes32` instead of `Float` would eliminate the circular import with no loss of information (since `Float` is `bytes32`).

---

## A03: `src/error/ErrFormat.sol`

### Evidence of Thorough Reading

- **File type:** File-level error definitions (no contract/library wrapper)
- **Pragma:** `^0.8.25` (line 3)
- **No imports**

**Errors defined:**

| Line | Error | Parameters |
|------|-------|------------|
| 7 | `UnformatableExponent` | `int256 exponent` |

**No functions, constants, or types defined.**

### Findings

No security findings.

The single error `UnformatableExponent` is used at `src/lib/format/LibFormatDecimalFloat.sol:85` to revert when an exponent value cannot be formatted. The parameter correctly provides the offending exponent for diagnosis. The NatSpec documentation is accurate.

---

## A04: `src/error/ErrParse.sol`

### Evidence of Thorough Reading

- **File type:** File-level error definitions (no contract/library wrapper)
- **Pragma:** `^0.8.25` (line 3)
- **No imports**

**Errors defined:**

| Line | Error | Parameters |
|------|-------|------------|
| 7 | `MalformedDecimalPoint` | `uint256 position` |
| 11 | `MalformedExponentDigits` | `uint256 position` |
| 16 | `ParseDecimalPrecisionLoss` | `uint256 position` |
| 19 | `ParseDecimalFloatExcessCharacters` | (none) |

**No functions, constants, or types defined.**

### Findings

#### A04-1 [LOW] `ParseDecimalFloatExcessCharacters` lacks a `position` parameter

All other parse errors (`MalformedDecimalPoint`, `MalformedExponentDigits`, `ParseDecimalPrecisionLoss`) include a `uint256 position` parameter identifying where in the input string the error occurred. `ParseDecimalFloatExcessCharacters` (line 19) has no parameters at all.

At the revert site (`src/lib/parse/LibParseDecimalFloat.sol:189`), the cursor position is available at the time of the revert -- the function knows exactly where the excess characters begin. Including this position in the error would improve debuggability and maintain consistency with the other parse errors.

This is LOW because it has no exploitable security impact but reduces the diagnostic quality of the error for callers/integrators.

---

## Summary

| ID | Severity | File | Title |
|----|----------|------|-------|
| A02-1 | INFO | ErrDecimalFloat.sol | `WriteError` duplicates `rain.datacontract` error and is unused |
| A02-2 | INFO | ErrDecimalFloat.sol | `WithTargetExponentOverflow` defined outside error file |
| A02-3 | INFO | ErrDecimalFloat.sol | Circular import between error and library files |
| A04-1 | LOW | ErrParse.sol | `ParseDecimalFloatExcessCharacters` lacks `position` parameter |
