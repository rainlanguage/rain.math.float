# Audit Pass 2 -- Test Coverage: `DecimalFloat.sol`

**Agent:** A01
**Source:** `src/concrete/DecimalFloat.sol`
**Test files examined:**
- `test/src/concrete/DecimalFloat.abs.t.sol`
- `test/src/concrete/DecimalFloat.add.t.sol`
- `test/src/concrete/DecimalFloat.ceil.t.sol`
- `test/src/concrete/DecimalFloat.div.t.sol`
- `test/src/concrete/DecimalFloat.eq.t.sol`
- `test/src/concrete/DecimalFloat.floor.t.sol`
- `test/src/concrete/DecimalFloat.frac.t.sol`
- `test/src/concrete/DecimalFloat.fromFixedDecimalLossless.t.sol`
- `test/src/concrete/DecimalFloat.fromFixedDecimalLossy.t.sol`
- `test/src/concrete/DecimalFloat.gt.t.sol`
- `test/src/concrete/DecimalFloat.gte.t.sol`
- `test/src/concrete/DecimalFloat.inv.t.sol`
- `test/src/concrete/DecimalFloat.isZero.t.sol`
- `test/src/concrete/DecimalFloat.lt.t.sol`
- `test/src/concrete/DecimalFloat.lte.t.sol`
- `test/src/concrete/DecimalFloat.max.t.sol`
- `test/src/concrete/DecimalFloat.min.t.sol`
- `test/src/concrete/DecimalFloat.minus.t.sol`
- `test/src/concrete/DecimalFloat.mul.t.sol`
- `test/src/concrete/DecimalFloat.parse.t.sol`
- `test/src/concrete/DecimalFloat.pow.t.sol`
- `test/src/concrete/DecimalFloat.sqrt.t.sol`
- `test/src/concrete/DecimalFloat.sub.t.sol`
- `test/src/concrete/DecimalFloat.toFixedDecimalLossless.t.sol`
- `test/src/concrete/DecimalFloat.toFixedDecimalLossy.t.sol`
- `test/src/concrete/DecimalFloat.constants.t.sol`
- `test/src/concrete/DecimalFloat.log10.t.sol`
- `test/src/concrete/DecimalFloat.pow10.t.sol`
- `test/src/concrete/DecimalFloat.format.t.sol`
- `test/src/concrete/DecimalFloat.integer.t.sol`
- `test/concrete/DecimalFloat.packLossless.t.sol`
- `test/concrete/TestDecimalFloat.sol`
- `test/concrete/TestDecimalFloat.unpack.t.sol`

---

## Source Contract: `DecimalFloat` (lines 9-320)

### Public State Variables (Constants)
| Name | Line |
|---|---|
| `FORMAT_DEFAULT_SCIENTIFIC_MIN` | 14 |
| `FORMAT_DEFAULT_SCIENTIFIC_MAX` | 19 |

### Functions
| Function | Line | Mutability |
|---|---|---|
| `maxPositiveValue()` | 24 | `pure` |
| `minPositiveValue()` | 30 | `pure` |
| `maxNegativeValue()` | 36 | `pure` |
| `minNegativeValue()` | 42 | `pure` |
| `zero()` | 48 | `pure` |
| `e()` | 54 | `pure` |
| `parse(string)` | 64 | `pure` |
| `format(Float, Float, Float)` | 78 | `pure` |
| `format(Float, bool)` | 89 | `pure` |
| `format(Float)` | 97 | `pure` |
| `add(Float, Float)` | 105 | `pure` |
| `sub(Float, Float)` | 113 | `pure` |
| `minus(Float)` | 120 | `pure` |
| `abs(Float)` | 127 | `pure` |
| `mul(Float, Float)` | 135 | `pure` |
| `div(Float, Float)` | 143 | `pure` |
| `inv(Float)` | 150 | `pure` |
| `eq(Float, Float)` | 158 | `pure` |
| `lt(Float, Float)` | 166 | `pure` |
| `gt(Float, Float)` | 175 | `pure` |
| `lte(Float, Float)` | 184 | `pure` |
| `gte(Float, Float)` | 193 | `pure` |
| `integer(Float)` | 200 | `pure` |
| `frac(Float)` | 207 | `pure` |
| `floor(Float)` | 214 | `pure` |
| `ceil(Float)` | 221 | `pure` |
| `pow10(Float)` | 228 | `view` |
| `log10(Float)` | 235 | `view` |
| `pow(Float, Float)` | 243 | `view` |
| `sqrt(Float)` | 250 | `view` |
| `min(Float, Float)` | 258 | `pure` |
| `max(Float, Float)` | 266 | `pure` |
| `isZero(Float)` | 273 | `pure` |
| `fromFixedDecimalLossless(uint256, uint8)` | 284 | `pure` |
| `toFixedDecimalLossless(Float, uint8)` | 293 | `pure` |
| `fromFixedDecimalLossy(uint256, uint8)` | 305 | `pure` |
| `toFixedDecimalLossy(Float, uint8)` | 316 | `pure` |

---

## Test Coverage Summary

### Functions WITH deployed-parity fuzz test coverage:
- `maxPositiveValue()` -- `DecimalFloat.constants.t.sol:testMaxPositiveValueDeployed`
- `minPositiveValue()` -- `DecimalFloat.constants.t.sol:testMinPositiveValueDeployed`
- `maxNegativeValue()` -- `DecimalFloat.constants.t.sol:testMaxNegativeValueDeployed`
- `minNegativeValue()` -- `DecimalFloat.constants.t.sol:testMinNegativeValueDeployed`
- `zero()` -- `DecimalFloat.constants.t.sol:testZeroDeployed`
- `e()` -- `DecimalFloat.constants.t.sol:testEDeployed`
- `parse(string)` -- `DecimalFloat.parse.t.sol:testParseDeployed`
- `format(Float, Float, Float)` -- `DecimalFloat.format.t.sol:testFormatDeployed`
- `add(Float, Float)` -- `DecimalFloat.add.t.sol:testAddDeployed`
- `sub(Float, Float)` -- `DecimalFloat.sub.t.sol:testSubDeployed`
- `minus(Float)` -- `DecimalFloat.minus.t.sol:testMinusDeployed`
- `abs(Float)` -- `DecimalFloat.abs.t.sol:testAbsDeployed`
- `mul(Float, Float)` -- `DecimalFloat.mul.t.sol:testMulDeployed`
- `div(Float, Float)` -- `DecimalFloat.div.t.sol:testDivDeployed`
- `inv(Float)` -- `DecimalFloat.inv.t.sol:testInvDeployed`
- `eq(Float, Float)` -- `DecimalFloat.eq.t.sol:testEqDeployed`
- `lt(Float, Float)` -- `DecimalFloat.lt.t.sol:testLtDeployed`
- `gt(Float, Float)` -- `DecimalFloat.gt.t.sol:testGtDeployed`
- `lte(Float, Float)` -- `DecimalFloat.lte.t.sol:testLteDeployed`
- `gte(Float, Float)` -- `DecimalFloat.gte.t.sol:testGteDeployed`
- `integer(Float)` -- `DecimalFloat.integer.t.sol:testIntegerDeployed`
- `frac(Float)` -- `DecimalFloat.frac.t.sol:testFracDeployed`
- `floor(Float)` -- `DecimalFloat.floor.t.sol:testFloorDeployed`
- `ceil(Float)` -- `DecimalFloat.ceil.t.sol:testCeilDeployed`
- `pow(Float, Float)` -- `DecimalFloat.pow.t.sol:testPowDeployed`
- `sqrt(Float)` -- `DecimalFloat.sqrt.t.sol:testSqrtDeployed`
- `min(Float, Float)` -- `DecimalFloat.min.t.sol:testMinDeployed`
- `max(Float, Float)` -- `DecimalFloat.max.t.sol:testMaxDeployed`
- `isZero(Float)` -- `DecimalFloat.isZero.t.sol:testIsZeroDeployed`
- `fromFixedDecimalLossless(uint256, uint8)` -- `DecimalFloat.fromFixedDecimalLossless.t.sol:testFromFixedDecimalLosslessDeployed`
- `toFixedDecimalLossless(Float, uint8)` -- `DecimalFloat.toFixedDecimalLossless.t.sol:testToFixedDecimalLosslessDeployed`
- `fromFixedDecimalLossy(uint256, uint8)` -- `DecimalFloat.fromFixedDecimalLossy.t.sol:testFromFixedDecimalLossyDeployed`
- `toFixedDecimalLossy(Float, uint8)` -- `DecimalFloat.toFixedDecimalLossy.t.sol:testToFixedDecimalLossyDeployed`
- `FORMAT_DEFAULT_SCIENTIFIC_MIN` / `FORMAT_DEFAULT_SCIENTIFIC_MAX` -- `DecimalFloat.format.t.sol:testFormatConstants`

### Functions with COMMENTED-OUT test (effectively untested at the concrete-contract level):
- `log10(Float)` -- `DecimalFloat.log10.t.sol` has the entire `testLog10Deployed` body commented out (lines 15-26)
- `pow10(Float)` -- `DecimalFloat.pow10.t.sol` has the entire `testPow10Deployed` body commented out (lines 15-26)

### Functions with NO test at all at the concrete-contract level:
- `format(Float, bool)` (line 89) -- No test file or test function exercises this overload
- `format(Float)` (line 97) -- No test file or test function exercises this single-argument default-formatting overload

---

## Findings

### A01-6 [LOW] `format(Float a, bool scientific)` overload has zero test coverage

**Location:** `src/concrete/DecimalFloat.sol:89`
**Fix:** `.fixes/A01-6.md`

The two-argument `format(Float a, bool scientific)` function, which provides raw boolean control over scientific notation formatting, has no test in any test file. While the underlying `LibFormatDecimalFloat.toDecimalString` is tested elsewhere, the concrete contract's wiring of this overload is unverified. This is the entry point used by off-chain consumers (Rust/WASM), so a wiring mistake would silently pass.

**Severity:** LOW -- The function is a trivial pass-through, but it is part of the public ABI consumed off-chain and should be validated.

### A01-7 [LOW] `format(Float a)` single-argument default overload has zero test coverage

**Location:** `src/concrete/DecimalFloat.sol:97`
**Fix:** `.fixes/A01-7.md`

The single-argument `format(Float a)` function, which applies the default scientific min/max constants and delegates to `format(Float, Float, Float)`, has no dedicated test. No test anywhere calls `deployed.format(a)` with a single argument. A mis-wiring of the constants or the internal delegation path would go undetected.

**Severity:** LOW -- It delegates to the tested 3-argument overload, but the default constant wiring path is itself untested.

### A01-8 [LOW] `format(Float, Float, Float)` require revert path is not tested

**Location:** `src/concrete/DecimalFloat.sol:79`
**Fix:** `.fixes/A01-8.md`

The `format(Float a, Float scientificMin, Float scientificMax)` function contains a `require(scientificMin.lt(scientificMax), ...)` guard at line 79. The test in `DecimalFloat.format.t.sol` uses `vm.assume(scientificMin.lt(scientificMax))` (line 19) to skip inputs that would trigger this revert, meaning the failure path is never exercised. No test verifies that the contract actually reverts with the expected message when `scientificMin >= scientificMax`.

**Severity:** LOW -- The require is a standard Solidity check and is unlikely to be wrong, but the test explicitly skips this path rather than covering it.

### A01-4 [LOW] `log10(Float)` deployed-parity test is entirely commented out

**Location:** `test/src/concrete/DecimalFloat.log10.t.sol:15-26`
**Fix:** `.fixes/A01-4.md`

The `testLog10Deployed` function body is fully commented out. The file contains only the `log10External` helper but no active test exercising `deployed.log10(a)`. This means the concrete contract's `log10` function -- which hardcodes `LibDecimalFloat.LOG_TABLES_ADDRESS` -- is not tested at the deployed-contract level. A mistake in the hardcoded address or the delegation would be undetected by these tests.

Note: The underlying `LibDecimalFloat.log10` is tested at the library level in `test/src/lib/LibDecimalFloat.log10.t.sol`, but that does not exercise the `DecimalFloat` concrete contract entry point.

**Severity:** LOW -- The library-level tests cover the math, but the concrete contract wiring (including the hardcoded `LOG_TABLES_ADDRESS`) is unverified.

### A01-5 [LOW] `pow10(Float)` deployed-parity test is entirely commented out

**Location:** `test/src/concrete/DecimalFloat.pow10.t.sol:15-26`
**Fix:** `.fixes/A01-5.md`

Same situation as A01-4. The `testPow10Deployed` function body is fully commented out. The concrete contract's `pow10` function, which hardcodes `LibDecimalFloat.LOG_TABLES_ADDRESS`, has no active deployed-parity test.

**Severity:** LOW -- Mirrors A01-4. The library math is tested but the concrete contract path is not.

### A01-9 [INFO] All fuzz tests use identical try/catch pattern

All 28 active deployed-parity tests follow the same structural pattern: deploy a fresh `DecimalFloat` contract, call an external helper via `this.functionExternal(...)` inside a try block, and compare results against the deployed contract. Reverts are forwarded. This pattern is solid for confirming that the concrete contract delegates correctly to the library. However, it tests only the equivalence between direct library calls and deployed calls -- it does not test specific known-value assertions for the concrete contract. The library-level tests elsewhere handle known-value coverage.

**Severity:** INFO -- Not a gap per se; the test strategy is deliberate. Noted for completeness.

---

## Finding Summary

| ID | Severity | Description |
|---|---|---|
| A01-4 | LOW | `log10(Float)` deployed-parity test entirely commented out |
| A01-5 | LOW | `pow10(Float)` deployed-parity test entirely commented out |
| A01-6 | LOW | `format(Float, bool)` overload has zero test coverage |
| A01-7 | LOW | `format(Float)` default overload has zero test coverage |
| A01-8 | LOW | `format(Float, Float, Float)` require revert path not tested |
| A01-9 | INFO | All fuzz tests use identical try/catch equivalence pattern |
