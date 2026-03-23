# Pass 5 -- Correctness / Intent Verification: LibDecimalFloatImplementation.sol

**Agent:** A09
**Date:** 2026-03-10

---

## Evidence of Thorough Reading

All 1307 lines of `src/lib/implementation/LibDecimalFloatImplementation.sol` were read in six overlapping chunks (lines 1-200, 200-400, 400-600, 600-800, 800-1000, 1000-1200, 1200-1307). Supporting files were also read: `src/error/ErrDecimalFloat.sol` (50 lines), `src/lib/table/LibLogTable.sol` (742 lines).

### Structural verification

- **Pragma:** `^0.8.25` (line 3)
- **License:** LicenseRef-DCL-1.0 (line 1), copyright 2020 (line 2)
- **Imports:** 6 error types from `../../error/ErrDecimalFloat.sol` (lines 5-12); 4 table constants from `../table/LibLogTable.sol` (lines 13-18)
- **File-level error:** `WithTargetExponentOverflow` (line 21)
- **File-level constants (6):** `ADD_MAX_EXPONENT_DIFF = 76` (line 24), `EXPONENT_MAX = type(int256).max / 2` (line 29), `EXPONENT_MIN = -EXPONENT_MAX` (line 34), `MAXIMIZED_ZERO_SIGNED_COEFFICIENT = 0` (line 37), `MAXIMIZED_ZERO_EXPONENT = 0` (line 40), `LOG10_Y_EXPONENT = -76` (line 44)
- **Library:** `LibDecimalFloatImplementation` (line 52)
- **22 functions verified:** minus (71), absUnsignedSignedCoefficient (89), unabsUnsignedMulOrDivLossy (116), mul (160), div (272), mul512 (466), mulDiv (479), add (610), sub (703), eq (724), inv (736), lookupLogTableVal (744), log10 (783), pow10 (902), maximize (957), maximizeFull (1011), compareRescale (1047), withTargetExponent (1127), intFrac (1169), mantissa4 (1197), lookupAntilogTableY1Y2 (1227), unitLinearInterpolation (1267)

### Magic numbers and bitmasks verified

- `0x7FFF` (line 758): 15-bit mask to strip ALT_TABLE_FLAG. Correct: ALT_TABLE_FLAG = 0x8000, so `& 0x7FFF` extracts the lower 15 bits.
- `0x8000` (line 759): ALT_TABLE_FLAG check. Correct: matches constant definition in `LibLogTable.sol`.
- `0xff` (line 674): used as `shr(0xff, ...)` to extract sign bit (bit 255) of int256. Correct: `shr(255, value)` shifts right by 255 bits, leaving only the sign bit.
- `1e75`, `1e76` (throughout): represent the coefficient magnitude boundaries. int256 can hold ~5.789e76 max, so maximized positive coefficients are in [1e75, 5.789e76] and maximized-with-extra-digit coefficients are in [1e76, 5.789e76].
- `1e72` (line 859): scaling factor for log table values. The raw table values are 4-digit numbers (0-9999). Multiplied by 1e72, they become 76-digit coefficients matching the system's precision.
- `1e73` and `1e72` (line 830): division scales for log10 index computation. For isAtLeastE76 (coeff in [1e76, 5.78e76]): dividing by 1e73 gives [1000, 5789]. For not (coeff in [1e75, 1e76)): dividing by 1e72 gives [1000, 9999]. These ranges correspond to the 9000-entry log table index [0, 8999].
- `ADD_MAX_EXPONENT_DIFF = 76` (line 24): maximum number of decimal digits in a coefficient. When exponent difference exceeds 76, one operand has zero contribution to the sum. Correct.
- `EXPONENT_MAX = type(int256).max / 2` (line 29): guard against overflow when maximizing (which subtracts from exponent). Dividing by 2 ensures room for the maximization's exponent decrease of up to ~77 digits.

---

## Function-by-Function Verification

### `minus` (line 71)

**Intent:** Negate a float.

**Verification:**
- `type(int256).min` cannot be negated directly because `|type(int256).min| = 2^255 > type(int256).max = 2^255 - 1`. The function correctly handles this by dividing by 10 and incrementing the exponent.
- Edge case: `type(int256).min, type(int256).max` correctly reverts with `ExponentOverflow` since incrementing the exponent would overflow.
- For all other values, `-signedCoefficient` is safe since the value is not `type(int256).min`.
- Result: **CORRECT**

### `absUnsignedSignedCoefficient` (line 89)

**Intent:** Return absolute value as unsigned.

**Verification:**
- `type(int256).min` case: returns `uint256(type(int256).max) + 1 = 2^255`. Correct: `|−2^255| = 2^255`.
- Negative case: `uint256(-signedCoefficient)`. Since `signedCoefficient != type(int256).min`, negation is safe. Cast to uint256 is safe because the negated value is positive.
- Non-negative case: direct cast. Safe because non-negative int256 fits in uint256.
- Result: **CORRECT**

### `unabsUnsignedMulOrDivLossy` (line 116)

**Intent:** Convert unsigned absolute result back to signed, applying sign based on original operand signs.

**Verification:**
- Sign detection via `(a ^ b) < 0`: XOR of two signed integers is negative if and only if they have different sign bits. Correct.
- When signs differ and result is exactly `uint256(type(int256).max) + 1 = 2^255`: returns `type(int256).min`. Correct, since that is the only negative int256 with absolute value 2^255.
- When signs differ and result > `type(int256).max` but not exactly `type(int256).max + 1`: divides by 10 and increments exponent. The division ensures the result fits in int256. The exponent increment compensates.
- When signs agree and result > `type(int256).max`: same divide-by-10 approach.
- **Potential issue:** `exponent + 1` on lines 132 and 144 is not inside an unchecked block, so it uses checked arithmetic. If exponent equals `type(int256).max`, this reverts with a Solidity panic rather than a meaningful error. However, in practice, exponents reaching `type(int256).max` would be caught earlier in `mul`/`div` by checked arithmetic on exponent sums. This is at most a poor error message issue.
- Result: **CORRECT** (minor UX issue with panic on extreme exponent)

### `mul` (line 160)

**Intent:** Multiply two floats using 512-bit intermediate.

**Verification:**
- Zero check: correctly returns maximized zero if either coefficient is zero.
- Exponent computation: `exponentA + exponentB` on line 175 is checked arithmetic (not in unchecked), so overflow reverts.
- 512-bit product: `mul512` returns (high, low). Only the high word is used (`prod1`) to estimate the number of decimal digits in the full 512-bit product that exceed 256 bits.
- Binary search + while loop for `adjustExponent`: counts decimal digits of `prod1`. See finding A09-19 below for comment inaccuracy.
- `mulDiv(A, B, 10^adjustExponent)` computes `(A*B) / 10^adjustExponent` using the full 512-bit product internally, then truncating to 256 bits. This correctly preserves precision by only dividing away the excess digits.
- `exponent += adjustExponent` adds back the decimal shift. Then `unabsUnsignedMulOrDivLossy` handles sign and potential lossy fit.
- Maximum adjustExponent: `prod1` can be at most `2^254 ~= 2.896e76`, which is a 77-digit number. The binary search + while loop produces adjustExponent = 77. `10^77 ~= 1e77 < type(uint256).max ~= 1.157e77`, so no overflow.
- Result: **CORRECT** (comment on adjustExponent range is wrong but logic is sound)

### `div` (line 272)

**Intent:** Divide two floats using 512-bit intermediate.

**Verification:**
- Division by zero: correctly reverted.
- Zero numerator: correctly returns maximized zero.
- Maximization: both operands are maximized to ensure sufficient precision.
- Scale selection: binary search finds the largest power-of-10 less than the denominator. The while loop on line 388 refines downward (`while (signedCoefficientBAbs <= scale)`) until `scale < signedCoefficientBAbs`. This is the correct invariant ensuring `mulDiv` does not overflow.
- `mulDiv(A, scale, B)` computes `(A * scale) / B`. Since `scale < B`, and `A < 2^256`, the result is guaranteed to be `< A`, which fits in uint256. The overflow check in mulDiv (`prod1 < denominator`) is satisfied because `prod1` of `A * scale` is at most `~A * B / 2^256`, and since both A and scale are at most ~5.78e76, `prod1 <= 5.78e76 * 5.78e76 / 1.157e77 ~= 2.89e76 < B` (since B >= 1e75 after maximization).
- Exponent handling: `exponentA - adjustExponent - exponentB` is correct for `(A * 10^adjustExponent / B) * 10^(exponentA - adjustExponent - exponentB) = A * 10^exponentA / (B * 10^exponentB)`.
- Underflow handling (lines 426-457): correctly detects when `exponentA - exponentB` would underflow int256, compensates by dividing the coefficient, and returns zero for extreme cases.
- Guard at line 398-399: reverts if A is not fully maximized when B is below 1e76. This is necessary because partial maximization of A with small B would cause precision loss in the mulDiv.
- Result: **CORRECT**

### `mul512` (line 466)

**Intent:** Compute full 512-bit product of two uint256 values.

**Verification:**
- Uses the standard Chinese Remainder Theorem approach from OpenZeppelin.
- `mulmod(a, b, not(0))` computes `(a*b) mod (2^256 - 1)`.
- `mul(a, b)` computes `(a*b) mod 2^256`.
- `high = mm - low - borrow` reconstructs the high word.
- This is a well-audited algorithm identical to OpenZeppelin's Math.sol.
- Result: **CORRECT**

### `mulDiv` (line 479)

**Intent:** Compute `(x * y) / denominator` with 512-bit intermediate.

**Verification:**
- Standard Remco Bloemen algorithm, used in OpenZeppelin, PRB Math, Solady.
- Overflow check: `prod1 >= denominator` correctly reverts (guarantees result fits in uint256 and denominator != 0).
- Remainder subtraction makes the 512-bit number exactly divisible.
- Lowest-power-of-two-divisor extraction and Newton-Raphson modular inverse are correct.
- Seed `(3 * denominator) ^ 2` is correct for 4-bit inverse: for odd `d`, `(3d) XOR 2` gives `d * inv = 1 mod 16`.
- 6 Newton-Raphson iterations double precision each time: 4 -> 8 -> 16 -> 32 -> 64 -> 128 -> 256 bits.
- Result: **CORRECT**

### `add` (line 610)

**Intent:** Add two floats with exponent alignment.

**Verification:**
- Zero operand shortcut: correctly returns the non-zero operand.
- Maximization: both operands are fully maximized to ensure similar coefficient magnitudes.
- Exponent alignment: the coefficient with the larger exponent is multiplied by 10^diff... wait, the code does the opposite -- it divides the coefficient with the SMALLER exponent. On line 657: `alignmentExponentDiff = exponentA - exponentB` (A has the larger exponent after swapping). Then line 666: `signedCoefficientB /= int256(10 ** alignmentExponentDiff)`. This divides B (the one with the smaller exponent) to align it to A's exponent. This is correct: bringing B to A's scale by dividing B and then adding at exponent A.
- `ADD_MAX_EXPONENT_DIFF = 76`: if the exponent difference exceeds 76, all of B's digits would be divided away. Early return of A is correct.
- Overflow detection (lines 673-677): standard signed overflow check using XOR of sign bits. `sameSignAB` checks if A and B have the same sign. `sameSignAC` checks if A and the result have the same sign. Overflow = sameSignAB AND NOT sameSignAC. Correct.
- Overflow handling (lines 679-691): divides both by 10 and increments exponent, then re-adds. Since both were maximized (magnitude >= 1e75), dividing by 10 gives at most ~5.78e75. Sum is at most ~1.156e76 < type(int256).max. Safe from re-overflow.
- Result: **CORRECT**

### `sub` (line 703)

**Intent:** Subtract two floats: A - B = A + (-B).

**Verification:**
- Calls `minus(B)` then `add(A, -B)`. Correct delegation.
- Result: **CORRECT**

### `eq` (line 724)

**Intent:** Numeric equality check.

**Verification:**
- Delegates to `compareRescale`, then checks equality of rescaled coefficients. Correct.
- Result: **CORRECT**

### `inv` (line 736)

**Intent:** Compute 1/x.

**Verification:**
- `div(1e76, -76, signedCoefficient, exponent)`. The value `1e76 * 10^-76 = 1`. So this computes `1 / x`. Correct.
- Using `1e76` as the numerator coefficient ensures maximum precision in the division.
- Result: **CORRECT**

### `lookupLogTableVal` (line 744)

**Intent:** Look up a log10 mantissa table value.

**Verification:**
- Main table: 2-byte entries, 900 entries (9000/10). `mainOffset = 1 + (index/10) * 2`. Skip 1 byte header, each entry 2 bytes. Correct.
- `extcodecopy(tables, 30, mainOffset, 2)`: copies 2 bytes into memory at offset 30, so `mload(0)` reads them as the least significant 2 bytes of a 32-byte word. Correct.
- ALT_TABLE_FLAG check: `and(mainTableVal, 0x8000)`. If set, uses alternate small table.
- Small table: 1-byte entries, indexed by `(index/100)*10 + (index%10)`. This transforms a 4-digit index ABCD into the 2-digit index AD (skipping the middle digits BC which are handled by the main table). The main table handles digits AB (index/10), the small table handles digit D (index%10) within group A (index/100). Correct decomposition.
- `smallTableOffset = LOG_TABLE_SIZE_BYTES + 1 = 1801`. If ALT_TABLE_FLAG: `smallTableOffset += LOG_TABLE_SIZE_BASE = 900`, giving `2701`. This correctly positions past the header (1), main log table (1800), and regular small table (900) if needed.
- Result: **CORRECT**

### `log10` (line 783)

**Intent:** Compute log10(x) using table lookup and interpolation.

**Verification:**
- Input validation: zero -> `Log10Zero`, negative -> `Log10Negative`. Correct.
- Exact power of 10: `signedCoefficient == 1e76` means the value is `1e76 * 10^exponent = 10^(exponent+76)`. Returns `(exponent+76, 0)`. Correct: `log10(10^n) = n`.
- Positive log (x >= 1): condition `exponent >= (isAtLeastE76 ? -76 : -75)`. If coefficient >= 1e76 with exponent >= -76, value >= 1. If coefficient < 1e76 (but >= 1e75) with exponent >= -75, value >= 1e75 * 10^-75 = 1. Correct.
- `powerOfTen`: the integer part of the log. For value = `coefficient * 10^exponent`, if coefficient is in [1e76, 5.78e76], then log10(value) = log10(coefficient) + exponent. And log10(coefficient) = log10(1e76 * mantissa) = 76 + log10(mantissa) where mantissa is in [1, 5.78]. So `powerOfTen = exponent + 76` gives the integer part of log10(value) when mantissa >= 1. Correct.
- Table lookup: index computation truncates to 4-digit precision, then uses linear interpolation between table entries for sub-grid precision. The log table stores `log10(1.XYZ) * 10000` (4 decimal digit values). Multiplied by 1e72, they become 76-digit coefficients at exponent -76.
- Negative log: `log10(x) = -log10(1/x)` for 0 < x < 1. Correct mathematical identity.
- Result: **CORRECT**

### `pow10` (line 902)

**Intent:** Compute 10^x using antilog table lookup and interpolation.

**Verification:**
- Negative x: `10^(-x) = 1/10^x`. Uses `minus` -> `pow10` -> `inv`. Correct.
- Splits into integer and fractional parts: `10^x = 10^int * 10^frac`.
- `intFrac` correctly separates integer and fractional parts of the coefficient.
- `mantissa4` extracts the first 4 digits of the fractional part for table lookup.
- Antilog table values represent `10^(idx/10000) * 10000`, stored as 4-digit integers. With yExponent = -4, they represent `10^(idx/10000)` in the range [1.000, 9.999].
- Linear interpolation between table entries for sub-grid precision.
- Final exponent: `1 + exponent + intPart`. The `1+` accounts for the fact that 10^frac is in [1, 10), so the coefficient from the table (e.g., 3162 for 10^0.5) needs exponent -3 rather than -4 to represent 3.162. Adding the integer exponent gives the correct power of 10.
- Edge case: the default y1=9997, y2=10000 for `idx == ANTILOG_IDX_LAST_INDEX` represents the values at 10^0.9999 and 10^1.0. 10^0.9999 = 9.9977, represented as 9997 (truncated) with exponent -4. 10^1 = 10, represented as 10000. Reasonable approximation.
- Overflow protection in interpolation (lines 930-934): the while loop shrinks scale and fracCoefficient until `(idxPlus1 * scale) / scale == idxPlus1`, preventing multiplication overflow. Correct.
- Result: **CORRECT**

### `maximize` (line 957)

**Intent:** Maximize coefficient magnitude by multiplying by powers of 10 and decreasing exponent.

**Verification:**
- Zero input: returns (0, 0, true). Correct.
- Binary search: successively tries 1e38, 1e19, 1e10, 1e2, 10 multiplications if the coefficient is still below 1e75. The thresholds (1e38, 1e57, 1e66, 1e74, 1e75) are correct: after multiplying by 1e38, the check `/ 1e57 == 0` is equivalent to "is the coefficient below 1e57?", in which case multiply by 1e19 brings it to at most 1e57-1 * 1e19 < 1e76.
- Exponent bounds: each multiplication is guarded by `exponent >= type(int256).min + N` to prevent exponent underflow. Correct.
- Final try (line 995): attempts `* 10` with overflow check via round-trip division. This pushes the coefficient into the [1e76, type(int256).max] range when possible.
- `full` flag (line 1001): `signedCoefficient / 1e75 != 0` means the coefficient's magnitude is at least 1e75. For negative values, Solidity integer division rounds toward zero, so `-1e75 / 1e75 = -1 != 0`. Correct.
- Works correctly for both positive and negative coefficients. The division `signedCoefficient / 1e75` rounds toward zero for negatives, so the check `== 0` means magnitude < 1e75.
- Result: **CORRECT**

### `maximizeFull` (line 1011)

**Intent:** Like maximize but reverts if not fully maximized.

**Verification:**
- Calls `maximize`, checks `full` flag, reverts with `MaximizeOverflow` if false. Straightforward.
- Result: **CORRECT**

### `compareRescale` (line 1047)

**Intent:** Rescale two floats for direct coefficient comparison.

**Verification:**
- Short-circuit cases (either zero, different signs, equal exponents): returns coefficients directly. For zero/different-sign cases, coefficient comparison gives correct ordering. For equal exponents, coefficients can be directly compared. Correct.
- Swap to ensure A has larger exponent. `didSwap` tracks this to maintain return order.
- Exponent difference overflow: `exponentDiff = exponentA - exponentB` in unchecked. The check `slt(exponentDiff, 0)` catches wrap-around from subtraction overflow. `sgt(exponentDiff, 76)` catches too-large differences. In both cases, returns `(signedCoefficientA, 0)` (or swapped), which correctly indicates A is the "larger" value since a huge exponent difference means A dominates.
- Rescaling: multiplies A's coefficient by `10^exponentDiff` to align to B's exponent. Overflow check via round-trip division. On overflow, returns the same dominant-A result.
- Return order respects `didSwap`. Verified with trace examples for both positive and negative cases.
- Result: **CORRECT**

### `withTargetExponent` (line 1127)

**Intent:** Adjust coefficient to match a target exponent.

**Verification:**
- Same exponent: return coefficient unchanged. Correct.
- Target > current: need to decrease coefficient (divide). `exponentDiff = targetExponent - exponent`. If diff > 76 or wraps to <= 0, returns zero (coefficient would be completely divided away). Correct.
- Target < current: need to increase coefficient (multiply). Overflow check via round-trip. Correct.
- Unchecked subtraction overflow: handled by the `<= 0` check on exponentDiff. If the subtraction wraps, the result is either very large positive (caught by > 76) or negative/zero (caught by <= 0). Correct.
- Result: **CORRECT**

### `intFrac` (line 1169)

**Intent:** Split a float into integer and fractional parts.

**Verification:**
- Non-negative exponent: entire value is integer, frac = 0. Correct.
- Exponent < -76: entire value is fractional, integer = 0. Correct (coefficient can have at most ~77 digits, so with exponent < -76 the value is always < 1).
- Exponent in [-76, -1]: `unit = 10^(-exponent)`, `frac = coefficient % unit`, `integer = coefficient - frac`. Solidity's `%` preserves the sign of the dividend, so `integer + frac = coefficient` always holds. Correct.
- Result: **CORRECT**

### `mantissa4` (line 1197)

**Intent:** Extract first 4 fractional digits for antilog table lookup.

**Verification:**
- Exponent = -4: coefficient is already 4 fractional digits. Correct.
- Exponent < -4: divide by `10^(-(exponent+4))` to get 4 digits. Interpolation flag set if there's a remainder. Correct.
- Exponent < -80: the fractional digits at positions 1-4 are all zero (coefficient has at most ~77 digits). Returns (0, interpolate, 1). Correct.
- Exponent >= 0: input is the fractional part from intFrac, which should be 0 for non-negative exponent. Returns (0, false, 1). Correct.
- Exponent in [-3, -1]: multiply up to 4 digits. E.g., exponent = -1: `coefficient * 10^3`. Since frac from intFrac is at most `10^(-exponent) - 1`, the product is at most `9 * 1000 = 9000` for exponent = -1. No overflow. Correct.
- Result: **CORRECT**

### `lookupAntilogTableY1Y2` (line 1227)

**Intent:** Look up two adjacent antilog table values.

**Verification:**
- Offset: `1 + 1800 + 900 + 100 = 2801`. This is: 1 byte header + 1800 bytes log main table + 900 bytes log small table + 100 bytes log small alt table. The antilog tables start at byte 2801 in the data contract. (Note: the actual computation uses named constants for the first two terms, magic numbers for the last two, as noted in pass 4.)
- The internal `lookupTableVal` function uses the same decomposition as `lookupLogTableVal` but for the antilog table: 2-byte main entries for groups of 10, 1-byte small entries for individual indices.
- The antilog main table has `2000` bytes (100 groups * 10 entries/group * 2 bytes/entry). So `offset := add(offset, 2000)` correctly advances past the main antilog table to the small antilog table.
- If `lossyIdx` is false, y2 is not looked up (optimization). Correct.
- Result: **CORRECT**

### `unitLinearInterpolation` (line 1267)

**Intent:** Linear interpolation: `y = y1 + ((x - x1) * (y2 - y1)) / (x2 - x1)`.

**Verification:**
- Short circuit when `x == x1`: returns `(y1, yExponent)`. Correct.
- Computes `(x - x1)`, `(y2 - y1)`, their product, then divides by `(x2 - x1)`, then adds `y1`. This is the standard linear interpolation formula.
- All intermediate computations use the library's own float arithmetic (sub, mul, div, add), so precision is limited to what the float system provides. This is by design.
- Result: **CORRECT**

---

## Findings

### A09-19 [INFO] Comment claims `adjustExponent [0, 76]` but actual range is [0, 77] in `mul`

**Severity:** INFORMATIONAL
**File:** `src/lib/implementation/LibDecimalFloatImplementation.sol`, line 208
**Status:** Open

The comment on line 208 states `adjustExponent [0, 76]` but the actual maximum value of `adjustExponent` is 77. The high word of the 512-bit product (`prod1`) can be as large as `2^254 ~= 2.896e76`, which is a 77-digit number. The binary search (37+18+9+4 = 68) plus the while loop (9 more iterations for a ~2.89e8 residual) yields 77.

This does not cause any functional issue:
- `int256(77)` fits in int256 trivially.
- `uint256(10) ** 77 = 1e77 < type(uint256).max ~= 1.157e77`, so no overflow.
- `mulDiv` correctly handles the larger divisor.

The comment should read `adjustExponent [0, 77]`.

### A09-20 [INFO] `unabsUnsignedMulOrDivLossy` produces Solidity panic instead of meaningful error on exponent overflow

**Severity:** INFORMATIONAL
**File:** `src/lib/implementation/LibDecimalFloatImplementation.sol`, lines 132, 144
**Status:** Open

`exponent + 1` on lines 132 and 144 uses checked arithmetic (the function is not inside an `unchecked` block). If `exponent == type(int256).max`, this reverts with a Solidity arithmetic panic (error code 0x11) rather than the library's `ExponentOverflow` error. In practice, this is nearly impossible to trigger because the callers (`mul`, `div`) use checked arithmetic on earlier exponent computations that would revert first. This is an informational note about inconsistent error messaging rather than a functional issue.

### A09-21 [INFO] `add` overflow recovery does not re-check for `signedCoefficientB` being zero after alignment division

**Severity:** INFORMATIONAL
**File:** `src/lib/implementation/LibDecimalFloatImplementation.sol`, lines 684-687
**Status:** Open

When `add` detects overflow on the sum `c = A + B` (line 671), it recovers by dividing both by 10 and re-adding (lines 684-687). At this point, `signedCoefficientB` was already divided by `10^alignmentExponentDiff` on line 666. If `alignmentExponentDiff` was close to 76, B may already be very small. Dividing by 10 again could make B zero, in which case the addition on line 687 is `signedCoefficientA/10 + 0`. The result is still mathematically correct (B is negligible), but worth noting that the recovery path can silently discard B entirely. This is consistent with the library's design philosophy of lossy arithmetic for extreme exponent differences.

### A09-22 [LOW] `div` scale selection binary search has a gap in the range [1e38, 1e43)

**Severity:** LOW
**File:** `src/lib/implementation/LibDecimalFloatImplementation.sol`, lines 310-385
**Status:** Open

The binary search tree for scale selection in `div` has the following structure for `signedCoefficientBAbs >= 1e38`:

```
if < 1e58:
    if < 1e48:
        if < 1e43: scale = 1e43, adjust = 43
        else: scale = 1e48, adjust = 48
    ...
```

When `signedCoefficientBAbs` is in the range [1e38, 1e43), the code sets `scale = 1e43, adjustExponent = 43`. However, the intent is to find the largest power of 10 strictly less than the denominator. For a value like `1e38`, we need `scale < 1e38`, but the binary search sets `scale = 1e43` and relies on the while loop (line 388) to refine downward.

The while loop `while (signedCoefficientBAbs <= scale)` will iterate: `1e43 -> 1e42 -> ... -> 1e37` (6 iterations). This is functionally correct -- the while loop always produces the right answer -- but it performs up to 5 extra iterations for values in this gap compared to what a tighter binary search would require.

Similarly, the lower branches have analogous gaps: [1e5, 1e10), [1e10, 1e14), [1e14, 1e19), [1e19, 1e23), [1e23, 1e28), [1e28, 1e33), [1e33, 1e38), [1e43, 1e48), [1e48, 1e53), [1e53, 1e58), [1e58, 1e63), [1e63, 1e68), [1e68, 1e73). Each gap can cause up to 5 extra while-loop iterations.

This is purely a gas efficiency issue, not a correctness issue. The while loop always converges to the correct scale. The binary search narrows to within ~5 OOM of the correct value, then the while loop handles the rest.

**Impact:** Minor gas overhead (up to 5 extra division + subtraction iterations) for certain denominator values. In worst case, ~5 * ~50 gas = ~250 extra gas.

---

## Summary

| ID | Severity | File | Issue |
|----|----------|------|-------|
| A09-19 | INFO | LibDecimalFloatImplementation.sol:208 | Comment says `[0, 76]` but actual `adjustExponent` range is `[0, 77]` |
| A09-20 | INFO | LibDecimalFloatImplementation.sol:132,144 | Panic instead of `ExponentOverflow` on extreme exponent |
| A09-21 | INFO | LibDecimalFloatImplementation.sol:684-687 | Add overflow recovery can silently zero out B |
| A09-22 | LOW | LibDecimalFloatImplementation.sol:310-385 | Div binary search has gaps causing extra while-loop iterations |

**LOW findings:** 1 (A09-22)
**INFORMATIONAL findings:** 3 (A09-19, A09-20, A09-21)

All 22 functions were verified to implement their claimed behavior correctly. The `mul512` and `mulDiv` implementations match the well-known OpenZeppelin/Remco Bloemen reference. Exponent handling in `add`, `sub`, `mul`, `div` was traced through with concrete examples and confirmed correct. All magic numbers and bitmasks were verified against their intended semantics.
