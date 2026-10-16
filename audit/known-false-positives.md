# Known false positives

## Equivalent mutant: `isPastEveryFloat` `excess > 67` arm at `> 68`

`src/lib/LibDecimalFloat.sol`, `isPastEveryFloat`. Moving the any-non-zero arm
from `excess > 67` to `excess > 68` changes nothing: at an excess of 68 the
mutant falls to the `excess >= 0` arm, where `(2^223 + 1) / 10^68` is 0, so
`magnitude > 0` is `magnitude != 0`, the original's answer.

## Equivalent mutant: `isPastEveryFloat` `excess >= 0` arm at `> 0`

`src/lib/LibDecimalFloat.sol`, `isPastEveryFloat`. Moving the floor-division arm
from `excess >= 0` to `excess > 0` changes nothing: at an excess of 0 the mutant
falls to the product arm, where `magnitude >= (2^223 + 2) × 10^0` is
`magnitude > 2^223 + 1`, the compare the original makes there.

## Equivalent mutant: `packLossy` lift from the shed coefficient

`src/lib/LibDecimalFloat.sol`, `packLossy`. Lifting `signedCoefficient` at
`exponent` instead of `initialSignedCoefficient` at `initialExponent` changes
nothing: the lift runs only when the value is not past every Float, and a shed
coefficient reaching it is past (the proof comment there), so nothing was shed
and the two pairs are equal.

## Equivalent mutant: `pow10` `NEVER_PAST_EXPONENT` gate shifted up to `int32.max + 26`

`src/lib/LibDecimalFloat.sol`, `pow10`. Moving the fast-exit gate anywhere from
`NEVER_PAST_EXPONENT` up to `int32.max + 26` changes nothing:
`LibDecimalFloatImplementation.pow10` returns `(1, k)` or a coefficient of at
most about 1e41, and such a coefficient is past every Float only at an excess of
27 or more over `int32.max` (1e41 × 10^26 is below 2^223 + 2), so no input can
tell the gates apart. `+ 1` and `+ 30` have both survived.

## Equivalent mutant: `pow` carry path `excess <= 67` guard at any bound from 27 up, or dropped

`src/lib/LibDecimalFloat.sol`, `packRoundedSignificant`. Changing
`excess <= 67 && isPastEveryFloat(roundedCoefficient, roundedExponent)` to
`excess <= k && ...` for any `k` from 27 up, or dropping the `excess <= 67`
term, changes nothing. `roundSignificant` returns a coefficient under 1e41
unchanged, so the rounded and unrounded pairs are then equal and both branches
check the same value: past reverts `ExponentOverflow(input)` either way, and not
past packs it either way. Otherwise the rounded coefficient is at least 1e40 (41
digits, or 1e41 on a carry), so at an excess of 28 or more the rounded value is
at least `1e68 × 10^int32.max`, past every Float, and the unrounded value is
within half a unit of the rounded one's last digit, at least
`(1e40 - 1/2) × 10^(int32.max + 28)`, past too: checking either reverts
`ExponentOverflow(input)`. At an excess of 27 a rounded coefficient from
`(2^223 + 2) / 1e27` up is past while the unrounded one can be below it, so
`k = 26` is not equivalent; `testPowCarryShedsTheUnrounded` kills it. `k = 66`
has survived.

## Equivalent mutant: signed `isPastEveryFloat` with int256.min as `2^255 - 1`

`src/lib/LibDecimalFloat.sol`, `isPastEveryFloat(int256, int256)`. Mapping
int256.min to a magnitude of `2^255 - 1` instead of `2^255` changes nothing: no
threshold falls between them. Every compare in the uint256 overload is against
at most `(2^223 + 2) × 10^9`, below both, so both are past at every exponent
above `NEVER_PAST_EXPONENT` and neither at or below it.

## Equivalent mutants: `div` `exponentB` guard boundary

`src/lib/implementation/LibDecimalFloatImplementation.sol`, `div`'s spill
branch. Changing `exponentB <= type(int256).max - adjustExponent` to `<` only
changes the outcome at `exponentB == type(int256).max - adjustExponent`, where
`underflowExponentBy` is `type(int256).max`, so the original returns the
`underflowExponentBy > 76` zero `(0, 0)`, the same as the mutant. No test can
distinguish them.

Changing it to `<= type(int256).max - adjustExponent - 1` changes the outcome
only at the same `exponentB`, where the mutant returns `(0, 0)` directly and the
original returns the same `(0, 0)` through `underflowExponentBy > 76`. The
comparison is free at its boundary in both directions.

## Equivalent mutant: frozen `mulDiv` copy, overflow check

`test/lib/LibDecimalFloatSqrtVariants.sol`, the private `mulDiv` copied from
26a3cf06 for `sqrtPre359` and `sqrtPr309`. Both call it as
`mulDiv(coefficient, scale, root)` with `scale` at most `1e6`, so
`prod1 = floor(coefficient * scale / 2^256) < 1e6`. The denominator is the
Newton root times `1e3` (`sqrtPre359`) or at least `1e2` (`sqrtPr309`); each
Newton step `(r + e / r) >> 1` is at least `r >> 1`, so from the `2^124` seed
the root is at least `2^118` after six steps, or `2^117 - 1` after seven and the
decrement, and the denominator at least `(2^117 + 1) * 1e2 > 1e37`.
`prod1 >= denominator` never holds, so `MulDivOverflow` never fires and relaxing
the check to `>` is equivalent. The `prod1 == 0` fast path is reachable, as the
frozen `scaleUp` has no domain check, so its mutants are not equivalent and are
pinned on wrapped negative coefficients, which the live sqrt rejects:
`testImplementationSqrtPre359MulDivFastPath` pins the quotient, with a zero
coefficient and with one whose quotient is odd;
`testImplementationSqrtPre359MulDivRemainderAndHighWord` pins the divisor, with
a remainder below the quotient so that `denominator + 1` lowers the quotient and
the Newton step's `>> 1` sees it, and pins the `prod1 == 0` gate, with a product
whose high word is exactly one, which a gate of `prod1 == 1` would divide as its
low word alone.

## Equivalent mutants: frozen `maximize` copy, step gates

`test/lib/LibFormatDecimalFloatPr321.sol`, the private `maximize` copied from
ce55522. The `E38`, `E57`, `E66` steps, the `E74` loop and the `E75` step each
multiply only while the coefficient is below a gate, and no step overshoots
`1e76` because every gate times its multiplier is at most `1e76`. Lowering the
`E57` gate to `1e56` or the `E66` gate to `1e65` only skips a step for
coefficients the loop and the final `x10` step then carry to the same
`[1e75, 1e76)` value with the same exponent shift. The gates are gas
distribution, not results; the exact `LibExactFloat.maximize` oracle in
`testFrozenMaximizeOracle` agrees with both. Lowering `E74` or `E75` by a decade
is not equivalent (the loop or the last step stop short) and is killed.

## Equivalent mutant: frozen `maximizeFull` copy, shortfall check

`test/lib/LibFormatDecimalFloatPr321.sol`, `maximizeFull` is private and reached
only from `_toScientific` with the exponent `unpack` read from a Float, so the
exponent is an int32 and `maximize` shifts it by at most 76: it cannot wrap
below `type(int256).min`, so the shortfall is always zero and any test of it
that still passes zero (`!= 0` to `> 1`) is equivalent.

## Equivalent mutants: frozen `packLossy` copy in the parse baseline

`test/lib/LibParseDecimalFloatPr321.sol`, the private `packLossy` copied from
ff6d70c. It is reached only from `parseDecimalFloat`, which returns
`ParseDecimalPrecisionLoss` with `Float.wrap(0)` whenever `lossless` is false,
so the packed float of a lossy result is never observed.

- Nearest-bound float: the bound path is taken only when shedding `k` digits
  left exactly `int224.max / 10`, which needs the coefficient after `k - 1`
  sheds to be `2^223` or `2^223 + 1`; lossless would need it to be a multiple of
  ten, and `2^223` ends in 8. So that path always returns `lossless` false and
  every bit of the float it packs is discarded: any change to the bound value
  (`type(int224).max`), its sign (`xor(sar(255, c), bound)`), its mask or its
  exponent (`boundExponent`) inside the `int32` branch is equivalent. Changing
  whether the branch is taken is not, and is killed.
- Shortcut gates `/ 1e72` raised to `/ 1e73`, and `/ 1e75` raised to `/ 1e76`:
  truncating division composes, `(c / 10^a) / 10^b == c / 10^(a + b)` toward
  zero, and each division by ten raises the exponent by one, so a shortcut only
  moves digits between one division and the loop. The loop stops at the first
  shed count `k` whose result fits int224, and a shortcut never passes it: a
  coefficient of magnitude at least `1e72` (or `1e75`) still has at least
  `1e67 > int224.max` (or `1e67`) after `5` (or `7`) sheds, so `k >= 5` (or
  `k >= 8`) in every case. With or without the shortcut the result is `c / 10^k`
  at `exponent + k`.
- `initialExponent > 0` relaxed to `>= 0`: the branch is entered only when the
  exponent left int32 after shedding, which raises it by at most ten, so an
  initial exponent of zero ends in `[0, 10]` and never reaches it.
- `!fits ||` dropped from the lift guard: when the coefficient did not fit
  int224, the headroom check that follows compares the initial coefficient with
  `int224.max / scale` for `scale >= 10`, which it exceeds, and reverts with the
  same `ExponentOverflow(initialSignedCoefficient, initialExponent)`.
- `exponent <= initialExponent` relaxed to `<`: at equality the general case
  takes the coefficient modulo `10 ** 0 == 1`, which is zero, the same `true`.

## Equivalent mutant: `baselines.rs` `code_only` keeps newlines

`crates/tests/src/baselines.rs`, `code_only` blanks comments and strings to
spaces but keeps their newlines. Blanking the newlines too changes nothing the
guard reads: `use_on`, the `using` check and `without_function` search for
substrings and match braces, none of which looks at line structure.

## Equivalent mutants: frozen `scaleUp` copy, step gates

`test/lib/LibDecimalFloatSqrtVariants.sol`, the private `scaleUp` copied from
26a3cf06 for `sqrtPre359`. Let the deficit be `76 - d` for a coefficient of `d`
digits, the digits it lacks to reach `[1e75, 1e76)`. Each step of size
`s in (38, 19, 10, 5, 3, 2, 1)` has the gate `c < 10^(76 - s)`, which holds iff
`s <= deficit`, and taking it lowers the deficit by `s`; the steps take the
deficit to zero greedily. Lowering a gate a decade, to `10^(75 - s)`, skips the
step only at `deficit == s` exactly, and the later steps then take the same `s`
digits: `38` as `19 + 10 + 5 + 3 + 1` (gate `1e38`), `19` as `10 + 5 + 3 + 1`
(`1e57`), `10` as `5 + 3 + 2` (`1e66`), `5` as `3 + 2` (`1e71`), `3` as `2 + 1`
(`1e73`). The coefficient and exponent come out the same, so these gates
distribute gas, not results. Lowering the `1e74` or `1e75` gate, raising any
gate to `<=`, or changing a multiplier or shift is not equivalent and is killed
(`testImplementationSqrtPre359ScaleUpGates` pins every gate at its boundary).

## Equivalent mutant: frozen `maximize` copy, outer gate

`test/lib/LibFormatDecimalFloatPr321.sol`, the `iszero(sdiv(c, E75))` gate
around `maximize`'s five steps forced true. Each inner step has its own gate
(`E38`, `E57`, `E66`, the `E74` loop and `E75`) that a coefficient of magnitude
at least `1e75` fails, so every step is a no-op for exactly the coefficients the
outer gate excludes. Only gas changes.

## Equivalent mutant: frozen `packLossy` copy, excess cap

`test/lib/LibParseDecimalFloatPr321.sol`, `excess > 67` relaxed to `> 68`. At an
excess of 68 the coefficient fits int224 (otherwise the `!fits` term reverts
first) and is nonzero (zero returned earlier), and `10 ** 68` fits int256;
`type(int224).max / 1e68` and `type(int224).min / 1e68` are both 0, so the
headroom check rejects every nonzero coefficient with the same
`ExponentOverflow(initialSignedCoefficient, initialExponent)`.

## Equivalent mutant: frozen `packLossy` copy, floor cap

`test/lib/LibParseDecimalFloatPr321.sol`, `shortfall > 67` relaxed to `> 68`. At
a shortfall of 68 the coefficient fits int224, shed until it did or fitting from
the start, so `|c| <= 2^223 < 1e68` and `c / 10 ** 68` is zero: the mutant
returns the same `(FLOAT_ZERO, false)` one line later.

## Equivalent mutant: frozen `packLossy` copy, ceiling branch

`test/lib/LibParseDecimalFloatPr321.sol`, `initialExponent > 0` raised to
`> 10`. The branch is entered only when shedding pushed the exponent past
`int32.max`, and shedding raises it by at most ten (a coefficient has at most 77
digits and int224 keeps 67), so an initial exponent in `[1, 10]` ends in
`[1, 20]`, inside int32, and the branch never sees it.

## Equivalent mutant: frozen `_toScientific` copy, `maximizeFull(10c, e - 1)`

`test/lib/LibFormatDecimalFloatPr321.sol`, `_toScientific` passing
`(signedCoefficient * 10, exponent - 1)` to `maximizeFull`. Both inputs are the
same value, and `maximize` returns the unique fully maximized form of a value:
the coefficient multiplied by the largest power of ten that keeps it inside
`[-int256.max, int256.max]` (its NatSpec, and `testFrozenMaximizeOracle` against
the digit-at-a-time `LibExactFloat.maximize`), with the exponent lowered by the
same count. The coefficient comes from `unpack`, so `|c| <= 2^223` and `10c`
fits int256; it is nonzero, as `toDecimalString` returns `"0"` first; and the
exponent is an int32, so neither input reaches the int256 floor and the
shortfall is zero for both, leaving `MaximizeOverflow`'s differing arguments
unreachable.

## Equivalent mutant: frozen `sqrtPr309`, Newton quotient over `root + 1`

`test/lib/LibDecimalFloatSqrtVariants.sol`, `sqrtPr309`'s
`root = (root + mulDiv(coefficient, scale, root)) >> 1` with the divisor
`root + 1`. Write `N = coefficient * scale` and `s = isqrt(N)`; the steps after
it decrement once if `root^2 > N`, then return `r + (N - r^2 > r)` for the
decremented `r`, which is `round(sqrt(N))` (the correct answer) whenever `r = s`
or `r = s - 1`: for `r = s` it adds one iff `N > s^2 + s`, the rounding
boundary; for `r = s - 1` it adds one always, since
`N - (s - 1)^2 >= 2s - 1 > r`, and `r = s - 1` arises only when
`sqrt(N) < s + 1/2` (below), where the answer is `s`.

Let `x` be the root fed to the step. `x >= sqrt(N)`: `x = (seed + 2) * k` with
`seed = isqrt(estimate)` and `sqrt(N) = sqrt(estimate') * k` for `k = 1e3` (or
`1e2`) and `estimate' - estimate < 1`, so `x - sqrt(N) > k`; and
`x - sqrt(N) <= 2k + 1 < sqrt(2x)` as `x > 1e39`. With
`floor((a + floor(b)) / 2)` equal to `floor((a + b) / 2)` for integer `a`:

- original, `x1 = floor((x + N / x) / 2)`: `x1 >= floor(sqrt(N)) = s` by AM-GM,
  and `x1 <= sqrt(N) + (x - sqrt(N))^2 / 2x < sqrt(N) + 1`, so `x1 <= s + 1` and
  the decrement leaves `r = s`;
- mutant, `x1' = floor((x + N / (x + 1)) / 2)`: with `y = x + 1`,
  `x + N / y = (y + N / y) - 1 >= 2 sqrt(N) - 1`, so
  `x1' >= floor(sqrt(N) - 1/2)`, which is `s` unless `sqrt(N) < s + 1/2`, and is
  `s - 1` at least; and `x1' <= x1 <= s + 1`.

So the mutant's `r` is `s` or, only below the half, `s - 1`, and both give the
original's result for every input.

The same line in `sqrtPre359` is not equivalent and is not covered by this
proof: its six Newton steps from `2^124`, with no decrement, need not reach
`isqrt(estimate)`. Inside the domain they leave the root within `5e10` of it and
the final step still converges, but the frozen `scaleUp` wraps a negative
coefficient to an estimate below `1e74`, where the step's input is `9e27` above
`sqrt(N)` and its quotient decides the root.
`testImplementationSqrtPre359UnconvergedNewtonStep` pins it.

## Equivalent mutant: pow oracle `k b` guard boundary

`crates/tests/src/differential.rs`, `check_pow_with`'s `|a| = 10^k` branch.
Changing `lead(&kb) >= 12` to `> 12` only changes the path at `lead(&kb) == 12`,
|k b| in [1e12, 1e13), where the original returns the `Truth::Past` band with
`over = rising`, `under = !rising`, `rising` the sign of k b, and the mutant
falls through. The two paths give every Solidity result the same verdict:

- k b whole: the mutant builds `e = 10^(k b)`, which fits an `isize` exponent,
  in a `Truth::Value` band that is `exact`, with
  `over = e > largest_float(negative)` and `under = e < smallest()`. For k b >=
  1e12, e is past the largest Float of either sign (under 10^2147483715) and not
  under the smallest, so `(over, under) = (true,
  false) = (rising, !rising)`;
  for k b <= -1e12, e is under the smallest Float (10^-2147483648) and not past
  the largest, so `(false, true) =
  (rising, !rising)`. A revert is therefore
  accepted or rejected exactly as under `Truth::Past`, with the same `input` for
  its data. A value result r is rejected by `Truth::Past` outright and by the
  exact band because `same(r, sign(e))` cannot hold: r decodes from a `bytes32`
  Float, so 0 < |r| < 10^2147483715 or r = 0, while |e| >= 10^1e12 or |e| <=
  10^-1e12.
- k b not whole: the mutant reaches the general band. `log10_of(10^k)` is
  exactly k (log10 of the coefficient 1 is 0), so z = k b exactly at 120 digits
  (at most 78 digits), |z| >= 1e12 > 2^33 = `huge()`, and the
  `magnitude(&z) > huge()` branch returns `range(rising, truth)` with the same
  `rising` (the sign of z = k b). Its `truth` is `Anywhere` only when
  `rel >= 1`: `rel = 5.00000012e-41 + N min(K1, K2 d)` with d =
  `distance_from_one(ax)` >= 9 for |k| >= 1, so `K2 d >= 1.35e-37 > K1` and the
  term is `N K1 <= 1e13 * 1.1728e-75 < 1e-61`, so `rel < 1` and `truth = Past`:
  the same band as the original.

The only distinguishing input is a `Dec` result whose exponent is past int32,
which no Float decodes to; the comparison is free at its boundary.

## Equivalent mutants: the parser's `NEVER_PAST_EXPONENT` gates before `isPastEveryFloat`

`src/lib/parse/LibParseDecimalFloat.sol`, `parseDecimalFloatInline` and
`parseDecimalFloatPastInt256`, the
`exponent > LibDecimalFloat.NEVER_PAST_EXPONENT &&` operand before each
`LibDecimalFloat.isPastEveryFloat` call. Changing either gate to `>=`, or
dropping it, changes nothing: the first statement of `isPastEveryFloat` is
`if (exponent <= NEVER_PAST_EXPONENT) return false;`, so the gate repeats the
callee's own short-circuit. Wherever the original gate is false the mutant calls
the function and gets `false`, the same value the original's `&&` produced, and
wherever the gate is true the two are the same expression. The gate only saves
the call on the hot path. Moving it the other way, to
`> NEVER_PAST_EXPONENT + 1`, is not equivalent, and
`testParseOverflowThresholdExcesses`,
`testParsePastInt256FirstExponentPastNeverPast` and
`testParsePastInt256GateAtNeverPastExponentPlusOne` kill it.

## Equivalent mutant: `.gas-snapshot` fuzz statistics

`.gas-snapshot`, observed through
`script/check-gas-snapshot.sh <committed> <fresh>`. Changing a committed fuzz
row's statistics,
`LibDecimalFloatAbsTest:testAbsNegative(int256,int32) (runs: 5096, μ: 2577, ~: 2838)`
to `(runs: 5096, μ: 9999, ~: 2838)`, cannot change the verdict. The verdict is a
function of `normalise(committed)` and `normalise(fresh)` alone, where
`normalise` rewrites every line ending in `(runs: N, μ: X, ~: Y)` to end in
`(fuzz)`. The original and the mutated file differ only in the `μ` field of one
such line, so `normalise` maps both to the same text, and for every fresh
snapshot the two give the same verdict. Fuzz rows comparing by name only is the
check's specified behaviour: fuzz gas is not reproducible across machines even
with a fixed seed.
