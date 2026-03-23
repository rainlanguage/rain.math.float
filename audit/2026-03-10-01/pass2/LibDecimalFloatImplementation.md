# Audit Pass 2 (Test Coverage) - LibDecimalFloatImplementation.sol

**Auditor:** A09
**Source file:** `src/lib/implementation/LibDecimalFloatImplementation.sol` (1307 lines)
**Test files:**
- `test/src/lib/implementation/LibDecimalFloatImplementation.minus.t.sol`
- `test/src/lib/implementation/LibDecimalFloatImplementation.sub.t.sol`
- `test/src/lib/implementation/LibDecimalFloatImplementation.mul.t.sol`
- `test/src/lib/implementation/LibDecimalFloatImplementation.inv.t.sol`
- `test/src/lib/implementation/LibDecimalFloatImplementation.add.t.sol`
- `test/src/lib/implementation/LibDecimalFloatImplementation.log10.t.sol`
- `test/src/lib/implementation/LibDecimalFloatImplementation.lookupLogTableVal.t.sol`
- `test/src/lib/implementation/LibDecimalFloatImplementation.maximize.t.sol`
- `test/src/lib/implementation/LibDecimalFloatImplementation.pow10.t.sol`
- `test/src/lib/implementation/LibDecimalFloatImplementation.div.t.sol`
- `test/src/lib/implementation/LibDecimalFloatImplementation.eq.t.sol`
- `test/src/lib/implementation/LibDecimalFloatImplementation.intFrac.t.sol`
- `test/src/lib/implementation/LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy.t.sol`
- `test/src/lib/implementation/LibDecimalFloatImplementation.withTargetExponent.t.sol`
- `test/lib/implementation/LibDecimalFloatImplementationSlow.sol` (reference impl)
- `test/lib/LibDecimalFloatSlow.sol` (reference impl)

---

## Evidence of Reading

### Source Functions (all 22)
| # | Function | Line | Has Direct Test File? |
|---|----------|------|-----------------------|
| 1 | `minus` | 71 | Yes |
| 2 | `absUnsignedSignedCoefficient` | 89 | No |
| 3 | `unabsUnsignedMulOrDivLossy` | 116 | Yes |
| 4 | `mul` | 160 | Yes |
| 5 | `div` | 272 | Yes |
| 6 | `mul512` | 466 | No |
| 7 | `mulDiv` | 479 | No |
| 8 | `add` | 610 | Yes |
| 9 | `sub` | 703 | Yes |
| 10 | `eq` | 724 | Yes |
| 11 | `inv` | 736 | Yes |
| 12 | `lookupLogTableVal` | 744 | Yes |
| 13 | `log10` | 783 | Yes |
| 14 | `pow10` | 902 | Yes |
| 15 | `maximize` | 957 | Yes |
| 16 | `maximizeFull` | 1011 | Indirect (via maximize tests) |
| 17 | `compareRescale` | 1047 | No |
| 18 | `withTargetExponent` | 1127 | Yes |
| 19 | `intFrac` | 1169 | Yes |
| 20 | `mantissa4` | 1197 | No |
| 21 | `lookupAntilogTableY1Y2` | 1227 | No |
| 22 | `unitLinearInterpolation` | 1267 | No |

### Error Paths
| Error | Used In | Tested? |
|-------|---------|---------|
| `ExponentOverflow` | `minus` (line 76), `add` (line 681) | Only `add` tested (add.t.sol line 139). `minus` ExponentOverflow path untested. |
| `DivisionByZero` | `div` (line 278) | Yes (div.t.sol line 38) |
| `MaximizeOverflow` | `div` (lines 395, 399), `maximizeFull` (line 1014) | Partially -- `div` tests MaximizeOverflow for denominator (div.t.sol line 50), but not the `scale == 0` path (line 395) or the `!fullA` path (line 399) directly. |
| `Log10Zero` | `log10` (line 795) | No |
| `Log10Negative` | `log10` (line 797) | No |
| `MulDivOverflow` | `mulDiv` (line 491) | No |
| `WithTargetExponentOverflow` | `withTargetExponent` (lines 1146, 1153) | Yes (withTargetExponent.t.sol lines 44, 67, 164, 211) |

### Test File Contents Summary

**minus.t.sol** (1 test): `testMinusIsSubZero` -- fuzz test comparing `minus(x)` to `sub(0, x)`. Bounds exponents to `EXPONENT_MIN/10..EXPONENT_MAX/10`. Does not test `type(int256).min` coefficient with `type(int256).max` exponent (the ExponentOverflow path).

**sub.t.sol** (4 tests): `testSubIsAdd` (fuzz), `testSubMinSignedValue` (fuzz), `testSubOneFromMax` (concrete), `testSubSelf` (fuzz). Good coverage of subtraction semantics.

**mul.t.sol** (11 tests): Mix of concrete and fuzz. Includes zero, negative, large coefficient, and exponent variation tests. Has a reference comparison (`testMulNotRevertAnyExpectation`) against `LibDecimalFloatSlow.mulSlow`. Solid coverage.

**div.t.sol** (9 tests): `DivisionByZero` tested. `MaximizeOverflow` tested for min-exponent denominator. Concrete and fuzz tests for division precision. No fuzz reference comparison against a slow implementation.

**add.t.sol** (9 tests): Extensive concrete examples, fuzz tests for identity/zero properties, exponent overflow tested. Good coverage.

**inv.t.sol** (4 tests): Reference comparison, gas test, `DivisionByZero` for inv(0). Good coverage.

**eq.t.sol** (8 tests): Extensive fuzz tests, reference comparison. Good coverage.

**maximize.t.sol** (4 tests): Idempotency, reference, concrete examples. Good coverage.

**withTargetExponent.t.sol** (10 tests): Comprehensive fuzz testing of all branches and error paths. Best-tested function.

**intFrac.t.sol** (4 tests): Concrete examples, fuzz tests for each exponent range. Good coverage.

**unabsUnsignedMulOrDivLossy.t.sol** (8 tests): Good sign-combination coverage. Tests for `c > type(int256).max` branches. Tests exact `type(int256).max + 1` edge case. Explicitly excludes `exponent == type(int256).max` with `vm.assume`.

**log10.t.sol** (5 tests): Exact powers of 10, exact lookups, interpolation, negative logs. No error path tests.

**pow10.t.sol** (5 tests): Exact powers, lookups, interpolation, range fuzz. No error path tests.

**lookupLogTableVal.t.sol** (1 test): Exhaustive spot checks at 100-index intervals across full range.

---

## Findings

### A09-11: Six internal functions have no direct test coverage (LOW)

**Functions without any dedicated test file:**
1. `absUnsignedSignedCoefficient` (line 89) -- Only called via `mul`, `div`, and `mulSlow` reference. No direct unit tests for edge cases like `type(int256).min`, `0`, `1`, `-1`.
2. `mul512` (line 466) -- Only called indirectly via `mul`, `div`, `mulDiv`. No direct tests for overflow behavior or specific 512-bit product verification.
3. `mulDiv` (line 479) -- Only called indirectly via `mul`, `div`. No direct test exercising the 512-bit division path or the `MulDivOverflow` error.
4. `compareRescale` (line 1047) -- Only called via `eq`. No direct tests. The `eq` tests indirectly cover it but do not isolate the rescaling logic or test the `didSwap` branches independently.
5. `mantissa4` (line 1197) -- Only called via `pow10`. No direct tests for boundary conditions (exponent exactly -4, exponent < -80, exponent in [-3, -1]).
6. `unitLinearInterpolation` (line 1267) -- Only called via `log10` and `pow10`. No direct tests. The `x1Coefficient == xCoefficient` short-circuit path is untested in isolation.

**Also no dedicated test:** `lookupAntilogTableY1Y2` (line 1227) -- only called via `pow10`.

**Impact:** These functions are exercised indirectly through higher-level function tests, which provides some coverage. However, edge cases specific to these functions (e.g., `mulDiv` with `prod1 >= denominator` triggering `MulDivOverflow`, or `absUnsignedSignedCoefficient` with `type(int256).min`) are not specifically targeted by any test.

---

### A09-12: `minus` ExponentOverflow error path untested (LOW)

**Location:** Source line 75-77, test file `LibDecimalFloatImplementation.minus.t.sol`

**Description:**
The `minus` function has a specific check for `signedCoefficient == type(int256).min && exponent == type(int256).max` that reverts with `ExponentOverflow`. This error path is never tested. The only test (`testMinusIsSubZero`) bounds exponents to `EXPONENT_MIN/10..EXPONENT_MAX/10`, which never reaches `type(int256).max`.

**Impact:** Low. The error path is unreachable through the packed Float API (32-bit exponents). However, as an internal function, it could be called from future code with wider exponent ranges.

---

### A09-13: `log10` error paths (`Log10Zero`, `Log10Negative`) completely untested (LOW)

**Location:** Source lines 794-798, test file `LibDecimalFloatImplementation.log10.t.sol`

**Description:**
The `log10` function reverts with `Log10Zero` when `signedCoefficient == 0` (after maximization) and with `Log10Negative` when `signedCoefficient < 0`. Neither error path is tested anywhere in the test suite. No `vm.expectRevert` test exists for either error.

The log10 tests only exercise positive inputs (exact powers of 10, positive lookups, and values that produce negative logs via the `inv` path).

**Impact:** Low. These are important domain-validity checks (log of zero and log of negative are mathematically undefined). Without tests, regressions that accidentally remove or alter these checks would go undetected.

---

### A09-14: `MulDivOverflow` error path in `mulDiv` untested (LOW)

**Location:** Source lines 490-492

**Description:**
The `mulDiv` function reverts with `MulDivOverflow(x, y, denominator)` when `prod1 >= denominator`. This error is never triggered in any test. The callers (`mul`, `div`) are designed to avoid this condition through their `adjustExponent` / `scale` logic. However, `mulDiv` is a `public` internal function that could be called from new code paths.

No test directly calls `mulDiv` with inputs that produce `prod1 >= denominator`.

**Impact:** Low. The check is a standard safety guard from the OpenZeppelin mulDiv pattern. It protects against division-by-zero and results that would exceed `uint256`. While unlikely to regress, having no test means the error selector and parameters are unverified.

---

### A09-15: `unabsUnsignedMulOrDivLossy` exponent overflow panic untested (relates to Pass 1 A09-1) (LOW)

**Location:** Source lines 132, 144; test file `LibDecimalFloatImplementation.unabsUnsignedMulOrDivLossy.t.sol`

**Description:**
Pass 1 finding A09-1 identified that `exponent + 1` at lines 132 and 144 will produce a raw `Panic(0x11)` (arithmetic overflow) rather than a custom `ExponentOverflow` error when `exponent == type(int256).max`. The test file explicitly avoids this case via `vm.assume(exponent != type(int256).max)` (lines 40, 87, 134, 163).

There is no test that verifies the behavior when `exponent == type(int256).max` and `signedCoefficientAbs > type(int256).max`. Whether the intent is to revert with `ExponentOverflow` or accept the raw panic, neither behavior is tested.

**Impact:** Low. This is the test coverage gap corresponding to the Pass 1 security finding. If A09-1 is fixed (adding an explicit `ExponentOverflow` check), a test should be added. Even if left as-is, a test documenting the expected `Panic(0x11)` behavior would be valuable.

---

### A09-16: `div` lacks a fuzz reference comparison test (INFORMATIONAL)

**Location:** Test file `LibDecimalFloatImplementation.div.t.sol`

**Description:**
The `mul` test suite includes `testMulNotRevertAnyExpectation` which compares the optimized `mul` against `LibDecimalFloatSlow.mulSlow` across random inputs. The `div` test suite has no equivalent fuzz reference test. Division is the most complex function in the library (~190 lines with a 16-way binary search for scale selection), making it the function most likely to benefit from a reference comparison.

The `inv` tests do compare against `LibDecimalFloatSlow.invSlow`, but that reference simply calls `div(1e37, -37, ...)`, so it does not independently verify division correctness.

**Impact:** Informational. The concrete tests for `div` are reasonably thorough (precision checks for 1/3, 1/9, division by 1, various OOM combinations). However, a fuzz reference test would provide stronger assurance that the binary search scale selection and exponent adjustment logic are correct across the full input domain.

---

### A09-17: `maximize` does not test the `full == false` return path directly (INFORMATIONAL)

**Location:** Source lines 957-1003, test file `LibDecimalFloatImplementation.maximize.t.sol`

**Description:**
The `maximize` function returns a `bool full` indicating whether the coefficient was fully maximized. The test file only calls `maximizeFull` (which reverts on `!full`). There is no test that calls `maximize` directly and asserts that `full == false` for specific inputs where the exponent is too small to allow further maximization.

The `full == false` case occurs when `exponent` is near `type(int256).min` and the coefficient cannot be multiplied further without underflowing the exponent. This path is used by `div` (lines 288-289) where partial maximization is acceptable.

**Impact:** Informational. The `full == false` path is exercised indirectly by `div` tests. However, no test explicitly verifies the boolean return value or checks the coefficient/exponent values when maximization is partial.

---

### A09-18: `div` internal error paths for `scale == 0` and `!fullA` are not specifically targeted (INFORMATIONAL)

**Location:** Source lines 395-399

**Description:**
Inside `div`, after the binary search for scale selection, there are two `MaximizeOverflow` reverts:
1. Line 395: `if (scale == 0)` -- this occurs if the denominator maximized to a very small value and the binary search loop reduced scale to zero. This would indicate an internal consistency error.
2. Line 399: `if (!fullA)` -- this occurs if the numerator could not be fully maximized.

The div test `testDivMinPositiveValueDenominatorRevert` triggers `MaximizeOverflow` via the `maximizeFull` call inside `div` (for the denominator `1, type(int256).min`), not via lines 395 or 399 specifically.

**Impact:** Informational. These are defensive checks for conditions that may be unreachable given `maximize`'s guarantees. Testing them would require constructing inputs that pass the initial `maximize` calls but still fail these checks.

---

## Summary

| ID | Severity | Title |
|----|----------|-------|
| A09-11 | LOW | Six internal functions have no direct test coverage |
| A09-12 | LOW | `minus` ExponentOverflow error path untested |
| A09-13 | LOW | `log10` error paths (`Log10Zero`, `Log10Negative`) completely untested |
| A09-14 | LOW | `MulDivOverflow` error path in `mulDiv` untested |
| A09-15 | LOW | `unabsUnsignedMulOrDivLossy` exponent overflow panic untested (A09-1 related) |
| A09-16 | INFORMATIONAL | `div` lacks a fuzz reference comparison test |
| A09-17 | INFORMATIONAL | `maximize` does not test `full == false` return path directly |
| A09-18 | INFORMATIONAL | `div` internal `scale == 0` and `!fullA` error paths not specifically targeted |

### Overall Assessment

The test suite provides good coverage for the core arithmetic operations (`add`, `sub`, `mul`, `div`, `eq`) and the higher-level functions (`log10`, `pow10`). Several functions have fuzz tests with reference implementations (`mul`, `inv`, `eq`, `maximize`), which provides strong regression assurance.

The main gaps are:
1. **Error path testing** -- Several custom errors (`Log10Zero`, `Log10Negative`, `MulDivOverflow`, `minus`'s `ExponentOverflow`) are never triggered in tests. This means changes to these guards would go undetected.
2. **Internal helper functions** -- Six functions (`absUnsignedSignedCoefficient`, `mul512`, `mulDiv`, `compareRescale`, `mantissa4`, `unitLinearInterpolation`) have no direct tests. They are exercised indirectly but their edge cases are not specifically targeted.
3. **The A09-1 gap** -- The `unabsUnsignedMulOrDivLossy` tests explicitly exclude the exponent overflow case that Pass 1 identified as having an inconsistent error type.
