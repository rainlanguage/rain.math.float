# Arithmetic specification

The rules every public operation of `LibDecimalFloat`, `LibParseDecimalFloat`
and `LibFormatDecimalFloat` follows, for maintainer sign-off (#438). Each rule
cites the ruling it comes from: a maintainer comment on the issue or PR, or the
body of a merged PR. A rule marked **UNRULED** describes what the code on main
does and has no ruling yet.

## Terms

- A Float is `c × 10^e`, `c` an int224 and `e` an int32, packed as `e` in the
  high 32 bits and `c` in the low 224.
- The domain of every operation is its parameter types: every `bytes32` is a
  Float, every `int256` pair a value, every `uint256` and `uint8` an input. No
  prose range narrows it.
- **Toward zero**: the closest Float whose magnitude does not exceed the exact
  value's.
- **Past every Float**: magnitude at least
  `(int224.max / 10 + 1) × 10^(int32.max + 1)`, where the closest Float toward
  zero would be above `int224.max × 10^int32.max`.
- **Below every Float**: non-zero with magnitude under `1 × 10^int32.min`.
- The largest Floats are not symmetric: `(2^223 - 1) × 10^int32.max` and
  `-2^223 × 10^int32.max`. "Past every Float" is one threshold for both signs,
  so a positive value up to three units of `10^int32.max` past
  `FLOAT_MAX_POSITIVE_VALUE`, and a negative value up to two units past
  `FLOAT_MIN_NEGATIVE_VALUE`, truncates into it (#452, PR #509).
- **Range errors**: `ExponentOverflow(c, e)` for a result past every Float,
  `ExponentUnderflow(c, e)` for a non-zero result below every Float. Neither
  saturates; nothing returns an infinity, NaN or negative zero (#333).
- Every arithmetic operation reverts `ExponentUnderflow` when its non-zero
  result rounds to zero; only `packLossy` returns that as `FLOAT_ZERO` with
  `lossless` false (#202, #149).
- Representations are not canonical; equality is numeric, never byte-level
  (#182).

## Packing

- `packLossy(c, e)` returns the Float toward zero of `c × 10^e` and `lossless`,
  true iff that Float equals the value (#333, #271, #284, #304).
- A coefficient past int224 sheds digits, truncating toward zero. If the shed
  coefficient has `|c| <= int224.max / 10` and `e - 1` fits int32, the result is
  `int224.max` (or `int224.min` for a negative value) at `e - 1`, lossless false
  (#333).
- An exponent below `int32.min` sheds digits to reach it; once every digit is
  shed the result is `FLOAT_ZERO`, lossless false (#271, #284).
- An exponent above `int32.max` multiplies the coefficient by ten per step to
  lower it, exactly; reverts `ExponentOverflow(c, e)` with the inputs when
  int224 has no headroom, which is exactly past every Float (#304, #333).
- Zero packs as `FLOAT_ZERO` (all bits zero), lossless true, for any `e`
  (**UNRULED**).
- `packLossless(c, e)`: as `packLossy`; reverts `ExponentOverflow(c, e)` for any
  value past `FLOAT_MAX_POSITIVE_VALUE` or `FLOAT_MIN_NEGATIVE_VALUE`, the band
  `packLossy` truncates into them included, and `LossyConversionToFloat(c, e)`
  for any other value that is not exactly a Float, below every Float included
  (#450, PR #509).
- `packArithmeticResult(c, e)`: as `packLossy`; reverts
  `ExponentUnderflow(c, e)` with its own inputs when a non-zero value packs to
  `FLOAT_ZERO` (#202). It finalises `add`, `sub`, `mul`, `integer`, `frac`,
  `floor`, `ceil`, `log10` and `sqrt`. `div`, `inv`, `pow` and `pow10` pack
  inline and their range errors report their input; `minus` and `abs` never
  revert (#333, #421).
- `unpack(f)` returns `(c, e)` sign-extended; never reverts (**UNRULED**).
- `canonicalize(f)`: the representative with the largest `|c|` that fits int224
  while `e >= int32.min`; `FLOAT_ZERO` for zero; `eq` to the input, idempotent,
  never reverts. Two Floats are `eq` iff their canonical forms are byte-equal
  (#182, PR #237).

## Exact operations

The default for every exact operation is the exact result rounded once toward
zero (#349, #350, #333). Floats are decimal: an exact result never takes a
binary path (#306).

### add, sub

- `add(a, b)` is the exact sum rounded once toward zero, whether the magnitudes
  add or cancel (#350, PR #434).
- It holds for every int256 coefficient and exponent the implementation is
  given, shedding from the exact sum (#394, #414).
- Cancellation bump: a cancelling operand that sheds digits in alignment is
  taken one unit up before the sum; one wholly below the larger operand's unit
  steps the sum one unit toward zero. Truncation then composes with packing (PR
  #434).
- `sub(a, b)` negates `b` exactly, unpacked, then sums as `add`. It is not
  `add(a, minus(b))`: `sub(-int224.max, int224.min)` is `1`, where
  `add(-int224.max, minus(int224.min))` is `0` (PR #436).
- Examples (PR #434): `1e100 + 1e-100 = 1e100`; `1e100 - 1 = (1e67 - 1)e33`;
  `1 - 1e-100 = 0.` then 67 nines; `1e100 - (1e33 + 1) = 1e100 - 2e33`;
  `1e100 - 1.7e33 = 1e100 - 2e33`.
- Errors: `ExponentOverflow` past every Float; `ExponentUnderflow` below every
  Float, both reporting the unpacked sum passed to packing (#202).

### minus, abs

- `minus(f)` is `-f` exact at the same exponent for every non-zero coefficient
  but `int224.min`, whose negation packs as `int224.max` at the same exponent;
  `FLOAT_ZERO` for zero at any exponent. Never reverts (#333).
- `abs(f)` is `f` for `f >= 0` (`FLOAT_ZERO` for zero) and `minus(f)` otherwise.
  `abs(int224.min × 10^e)` is `int224.max × 10^e`. Never reverts (#333).

### mul

- `mul(a, b)` is the exact product rounded once toward zero (#349, #333). The
  product is formed in 512 bits and truncated toward zero to an int256
  coefficient, then packed.
- An exponent sum below `int256.min` sheds digits to the floor and is zero once
  every digit is shed (PR #300).
- Errors: `ExponentOverflow` past every Float, including an exponent sum past
  `int256.max` (PR #307, #325); `ExponentUnderflow` below every Float (#202).
  Each reports the unpacked product passed to packing, except the int256-ceiling
  case, which reports `a`.
- No 512-bit or 256-bit intermediate of `mul`, `div` or `inv` overflows for any
  pair of Floats: their only errors are `ExponentOverflow`, `ExponentUnderflow`
  and `DivisionByZero` (PR #443).

### div, inv

- `div(a, b)` is the exact quotient rounded once toward zero (#349, PR #421).
  The quotient is first truncated toward zero at `10^(ua - lb)`, `ua` the
  dividend's int256 unit and `lb` the exponent of the divisor's leading digit,
  keeping 75 to 77 digits; packing truncates again, which composes (PR #421).
- `div` with `b` zero reverts `DivisionByZero(c_a, e_a)`.
- `div` range errors report `a`, unpacked: `ExponentOverflow` past every Float,
  `ExponentUnderflow` below every Float (#421, #338, #329).
- `inv(f)` is `div(1, f)`. `inv(0)` reverts `DivisionByZero(0, e)` with its own
  input. No inverse is past every Float (`1 / 1e-2147483648` is
  `10 × 10^int32.max`), so `inv` never overflows; below every Float reverts
  `ExponentUnderflow` reporting `f` (PR #421).
- `0 / b` is `FLOAT_ZERO` for non-zero `b` (**UNRULED**).

### integer, frac, floor, ceil

All **UNRULED**.

- `integer(f)` truncates toward zero at `f`'s exponent; `frac(f)` is
  `f - integer(f)` at the same exponent, carrying `f`'s sign. Exponent `>= 0`:
  `integer` is `f`, `frac` is zero. Exponent `< -76`: `integer` is zero, `frac`
  is `f`.
- `floor(f)`: `f` when `e >= 0` or the fraction is zero; otherwise `integer(f)`
  for `f > 0` and `integer(f) - 1` for `f < 0`.
- `ceil(f)`: `f` when `e >= 0` or the fraction is zero; otherwise
  `integer(f) + 1` for `f > 0` and `integer(f)` for `f < 0`.
- None reverts: each result is zero exactly or at least 1 in magnitude, so
  `packArithmeticResult` never underflows, and none lifts the exponent above
  `int32.max`.

## Comparison and predicates

- `eq(a, b)` is numeric equality; `0 × 10^x` equals `0 × 10^y` for all `x`, `y`
  (#182). Exact for every pair; never reverts.
- `lt`, `gt`, `lte`, `gte` compare numerically, exactly, for every pair; never
  revert (**UNRULED**).
- `min(a, b)` is `lt(a, b) ? a : b` and `max(a, b)` is `gt(a, b) ? a : b`: on a
  tie both return `b`, byte for byte (**UNRULED**).
- `isZero(f)` is true iff the coefficient is zero, any exponent (**UNRULED**).
- `isOdd(f)` is true iff `f` is an odd whole number; exact, no division or
  modulo of Floats; never reverts (**UNRULED**).

## agree

- `agree(absolute, proportional, lowest, highest)` is
  `|highest - lowest| <= max(absolute, proportional × max(|lowest|, |highest|))`,
  computed unpacked, never packed back, so it answers for every representable
  set instead of reverting (PR #278).
- The spread is the implementation `sub`, so on a cancelling spread it truncates
  toward zero like `sub`; a spread accepted at the boundary exceeds the limit by
  under `1e-76` of its magnitude (PR #278, PR #434).
- The extremes may come in either order: `agree(a, p, x, y)` equals
  `agree(a, p, y, x)`; a negative spread is negated before the comparison (#481,
  PR #498).
- A negative tolerance reverts `AgreeToleranceNegative(absolute, proportional)`;
  neither tolerance positive reverts
  `AgreeNoPositiveTolerance(absolute, proportional)`. Either alone may be zero
  (PR #281).

## Fixed-decimal conversions

- `fromFixedDecimalLossy(v, d)`: `(v, -d, true)` for `v <= int256.max`;
  otherwise `(v / 10, -d + 1, v % 10 == 0)` (**UNRULED**).
- `fromFixedDecimalLossyPacked(v, d)`: `packLossy` of the above; lossless iff
  both steps are (**UNRULED**).
- `fromFixedDecimalLossless(v, d)` and `fromFixedDecimalLosslessPacked(v, d)`:
  as above; any loss reverts `LossyConversionToFloat` with
  `fromFixedDecimalLossy`'s coefficient and exponent. No `uint256` at up to 255
  decimals is past every Float (**UNRULED**).
- `toFixedDecimalLossy(f, d)` is `c × 10^(e + d)` truncated toward zero, with
  `lossless` true iff nothing was truncated (**UNRULED**).
- A negative coefficient reverts `NegativeFixedDecimalConversion(c, e)`; zero is
  `(0, true)` at any exponent (**UNRULED**).
- `e + d < -77` with a non-zero coefficient is `(0, false)` (**UNRULED**).
- A value at or above `2^256` reverts `FixedDecimalOverflow(c, e, d)`, int256
  overflow of `e + d` included (PR #203).
- `toFixedDecimalLossless(f, d)`: any truncation reverts
  `LossyConversionFromFloat(c, e)` (**UNRULED**).

## Approximations

`log10`, `pow10` and `pow` round an internal approximation to nearest at 41
significant digits, half away from zero; their contract is the bound, and near a
tie either neighbour may result (#349, #350). `sqrt` is correctly rounded
(#432). None is moved to toward zero (#350).

Exact results stay exact: `pow10(k) = 10^k` and `log10(10^k) = k` for integer
`k`; integer and fractional powers, roots included, with at most 41 significant
digits (#306).

### sqrt

- Correctly rounded to nearest at 41 significant digits: within half a unit in
  the 41st digit, under `5e-41` relative, monotone (#432). Proof: NatSpec of
  `LibDecimalFloatImplementation.sqrt`; four Newton steps (#432).
- `sqrt(0)` is `0`. A negative argument reverts `PowNegativeBase(c, e)`
  (**UNRULED**: the error chosen).
- The root's exponent is half the input's, so it always packs.

### log10

- Within half a unit in the 41st digit plus `1.0037e-50` absolute (#435). Raw
  error `1.0037e-50` proven in the NatSpec of `log10Unrounded`, from
  `log10Reduce` and `log10Ratio` (#435).
- `log10(0)` reverts `Log10Zero()`; a negative argument reverts
  `Log10Negative(c, e)` (**UNRULED**).
- `log10(1)` is `0`.

### pow10

- Within half a unit in the 41st digit plus `1.12e-8` of a unit, under
  `5.00000012e-41` relative; raw error `111.11` units before rounding (#435).
  `exp10Fixed` is within `88.08` units, `1.408e-49` relative, proven by
  enumerating every step in `crates/tests/src/fixed.rs` (#435).
- `pow10(0)` is `1` at any zero exponent.
- An integer part past int256 reverts `ExponentOverflow(input)` for a positive
  argument and `ExponentUnderflow(input)` for a negative one.
- A result past every Float reverts `ExponentOverflow` and one below every Float
  `ExponentUnderflow`, both reporting the call's input (#421, #338, #329).
- A result below `1e-2147483608` sheds digits to reach the int32 floor, so its
  bound adds `1e-2147483648` absolute (#435).

### pow

- `pow(a, b)` within `5.00000012e-41 + N × min(K1, K2 × d)` relative, `N` the
  integer part of `|b|`, `d = max(|a|, 1/|a|) - 1`; `K1 = 1.7273e-76`,
  `K2 = 1.5e-38` for `b > 0`; `K1 = 1.1728e-75`, `K2 = 3.4786e-38` for `b < 0`
  (#428, #424). Proof: NatSpec of `LibDecimalFloat.pow`.
- The integer part is exact by squaring; the fractional part is
  `10^(frac(b) × log10(a))` with guard digits; a fractional part of exactly a
  half is the correctly rounded root of `a^(2N + 1)` (PR #358, #432).
- `a^1` and integer powers are rounded to 41 digits like every other power
  (**UNRULED**).
- `0^0 = 1`, `a^0 = 1`, `0^b = 0` for `b > 0`; `0^b` for `b < 0` reverts
  `ZeroNegativePower(b)` (#86).
- `1^b = 1` for every `b` (**UNRULED**).
- A negative `a` with a whole `b` is `(-a)^b`, negated for odd `b`; with a
  fractional `b` reverts `PowNegativeBase(c_a, e_a)`, reporting `a` unpacked
  (#88, PR #289, PR #443).
- Range errors report `a`, unpacked (#421, #338, #329).
- The squaring loop reverts `ExponentOverflow` / `ExponentUnderflow` once the
  base exponent passes `±int128.max` (#244, #276).
- An integer part of `|b|` past int256 reverts `ExponentOverflow` when `a` (or
  `1/a` for `b < 0`) is at least 1 and `ExponentUnderflow` otherwise
  (**UNRULED**).
- A product that rounding would carry past every Float is instead truncated to
  int224, under `1e-67` relative (**UNRULED**).
- A result below `1e-2147483608` sheds digits to the floor and its bound adds
  `1e-2147483648` absolute; below every Float reverts `ExponentUnderflow`
  (**UNRULED**).

## Constants

- `FLOAT_E` and `FLOAT_PI`: the closest Float not above e and π, the 67-digit
  coefficient at exponent `-66` truncated at 66 places; checked by
  `crates/tests` against e and π derived independently (PR #274, #503, PR #520).
- `FLOAT_ZERO`, `FLOAT_ONE`, `FLOAT_HALF` (`5e-1`), `FLOAT_TWO`;
  `FLOAT_MAX_POSITIVE_VALUE` (`int224.max`, `int32.max`),
  `FLOAT_MIN_POSITIVE_VALUE` (`1`, `int32.min`), `FLOAT_MAX_NEGATIVE_VALUE`
  (`-1`, `int32.min`), `FLOAT_MIN_NEGATIVE_VALUE` (`int224.min`, `int32.max`)
  (**UNRULED**).

## Parsing

- `parseDecimalFloat(str)` returns `(selector, Float)`; errors are returned by
  value, chosen by the literal's value; a well-formed literal never reverts
  (#375, PR #433, #510).
- Grammar: optional `-`, integer digits, optional `.` and digits, optional `e`
  or `E` with optional `+` or `-` and digits (PR #248). At most one `-` on each
  of coefficient and exponent (PR #290). No thousands separators (#151).
- A literal exactly a Float returns `(0, f)`.
- `ExponentOverflow`, by value and never as a revert from packing, for every
  literal at least `(2^223 + 2) × 10^int32.max` in magnitude, an exponent past
  int256 included (PR #433, #510).
- `ParseDecimalPrecisionLoss` for any other literal not exactly a Float: the
  band below that threshold past the largest Float of its sign, a coefficient
  past int256, and underflow to zero (PR #433, #510). `ParseDecimalOverflow` is
  gone (#375).
- `ParseDecimalFloatExcessCharacters` for a well-formed literal followed by more
  input (PR #433).
- Malformed literals keep their own selector: `ParseEmptyDecimalString` (no
  integer digits), `MalformedDecimalPoint` (`.` without digits),
  `MalformedExponentDigits` (`e` without digits) (PR #433).
- An all-zero fraction parses exactly as no fraction (PR #328).

## Formatting

- `toDecimalString(f, scientific)`: the caller chooses notation, no threshold
  (#138). Zero is `"0"`.
- Every Float whose string parses back exactly is formatted (#376, PR #427).
- Scientific: `d.ddd` then `eN` from the most significant digit; `e0` is omitted
  (**UNRULED**: the exact shape).
- Plain: the only cap is `|e| <= 1000` (`MAX_NON_SCIENTIFIC_EXPONENT`) on the
  canonical exponent, after the coefficient's trailing zeros are stripped, so
  equal Floats format alike; outside it reverts `UnformatableExponent(e)` with
  the canonical exponent (#376, PR #427, #449, PR #496).

## Range guards

Named errors at the internal guards (#429, closes #422; #336):

| Function                        | Error                                    | Fires when                                                                                                             |
| ------------------------------- | ---------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `mulDivFixed`, `mulDiv`         | `MulDivOverflow(x, y, d)`                | the 512-bit quotient is past uint256, or `d` is zero (#486)                                                            |
| `log10Ratio`                    | `Log10RatioOutOfRange(a, b)`             | `a + b` past uint256, `b` zero, or z past the proven series range                                                      |
| `log10Ratio` (relative)         | `Log10RatioRelativeSumTooSmall(a, b)`    | `a + b < 1e50` (#336)                                                                                                  |
| `log10Unrounded`                | `ExponentOverflow(input)`                | characteristic past int256                                                                                             |
| `sqrt` (implementation)         | `SqrtOutOfRange(c, e)`                   | `c` outside `(0, 1e76)`; every exponent has a root (#451, PR #497)                                                     |
| `exp10Fixed`                    | `Exp10FixedOutOfRange(x)`                | `x` outside `[0, 1)` at the 1e50 scale                                                                                 |
| `log10Reduce`                   | `Log10ReduceOutOfRange(x)`               | `x` outside `[1e75, 1e76)`                                                                                             |
| `absCoefficient`                | `AbsCoefficientOverflow(c)`              | `c` is `int256.min`                                                                                                    |
| `scaleUp`                       | `ScaleUpOutOfRange(c, e)`                | `c` outside `(0, 1e76)` or the shift passes `int256.min`                                                               |
| `unabsUnsignedMulOrDivLossy`    | `UnabsExponentOverflow(a, b, abs, e)`    | a magnitude past int256 at the result's sign must shed a digit at `e = int256.max` (#502, PR #518)                     |
| `readSignificantDigits` (parse) | `ParseDecimalNoSignificantDigits(start)` | a mantissa with no nonzero digit is read; unreachable from the parse entry points, which pass only a mantissa with one |

- `withTargetExponent(c, e, t)` truncates toward zero when shrinking; growing by
  `d` digits returns `c × 10^d`, zero for zero at any `d`, and reverts
  `WithTargetExponentOverflow` iff `c × 10^d` is outside int256 (#367, ruled A).
- `log10Ratio` within `1.0036` units (fixed) or `C × 8.03e-50 + 1` (relative)
  for `z <= 5.1e-4` (#435).
- `MaximizeOverflow(c, e)` from `maximizeFull` (**UNRULED**).
