# Known false positives

Mutants that survive because the mutated program agrees with the original on
every input, and mutants a later change removed ("Resolved by removal"). Each
entry carries the proof; a sampled or "no known input" argument is not one.

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

## Equivalent mutants: `LibHalmosExact` hint filters, `hasDigits`, `abs`, `eqValue` and the slice defaults

`test/halmos/LibHalmosExact.sol`.

The hint filters (`divHint`, `shiftHint`, `timesTenHint`, `maximizeHints`,
`packHints`) are true for every input in their domain, and being true is the
only property forge observes of them (`test/halmos/LibHalmosExact.t.sol` asserts
it; the `divhint`, `hints` and `hints-pack` halmos lemmas prove it). So any
mutant of a hint filter that keeps it true on its domain is equivalent under
forge, `return true` included: a dropped conjunct (`c / 1e72`, the int224 early
return, an `isQuotient`), a moved threshold (`j >= 76`, `while (m > 67)`,
`>= 74`), a changed step (`+= 37`, `+= 39`, `+= 20`, `+= 11`, `+= 3`, `+= 2`;
those reaching s + j = 76 with s > 0 wrap the shifted product, and a wrapped
product is still outside [-T10, T10] and nonzero divided by 10^t), or `T10` as
`int256.max / 11` (`timesTenHint` is an identity for any constant at most
int256.max). Such a change only moves which terms the halmos branch solver is
handed a fact for, which the filters' NatSpec names as costing completeness (a
loop-bound warning or extra paths), never soundness; a lemma run proving without
a warning is what pins the picks, not a forge test. That run is a manual
dispatch of the halmos workflow, which is disabled on the repository.

- `hasDigits`: dropping `c != 0 &&`. For c = 0, `x >= 10 ** j` is false for
  every j (10^j is at least 1); for c nonzero the term is true.
- `abs`: `x < 0` to `x <= 0`. Only x = 0 changes branch, and -0 is 0.
- `inSlice`, `overlapsSlice`: the `envOr` defaults with the env unset.
  `testSlices` pins the defaults [0, uint256.max] through empty variables, which
  `envOr` reads as unset; a mutant that survives it keeps them. Every lemma that
  calls them is sliced in the matrix and runs with both set.
- `eqValue`: `&&` for the zero test's `||`. With exactly one coefficient zero
  the sign test passes only for a positive other, where the product test
  compares zero against a nonzero product under its overflow guard: false, as
  the original.
- `eqValue`: `re > se` for `re >= se`. At re = se both branches have d = 0, p =
  1 and compare r with s.
- `eqValue`: `d > 76` or `d > 78` for `d > 77`, either branch. At d = 77 the
  product is at least 10^77 > 2^255, above every magnitude. At d = 78 the
  wrapped `10 ** 78` exceeds 2^255, so `max / p` is 1 and the product test needs
  a magnitude of p: false either way.
- `eqValue`: `<` for the overflow guard's `<=`, either branch. At r = floor(max
  / p) the product r p is above 2^256 - 1 - p > 2^255 for d <= 76 and is 10^77 >
  2^255 for d = 77, above every magnitude, so the equality is false with the
  guard either way.

## Equivalent mutant: `isMaximized`'s upper bound

`test/halmos/AddSubRoundOnce.halmos.t.sol`, `isMaximized`. Changing
`x <= 10 * LibHalmosExact.T10` to `<` drops |m| = 10 T10 from the inputs IDEM,
NEAR and FAR check, the lemmas that return when it is false. Halmos cannot kill
a change that only narrows a lemma's precondition, so the mutant survives the
halmos oracle; it is equivalent for the composition because that magnitude is
never a maximized coefficient. 10 T10 = 10 floor((2^255 - 1) / 10) = 2^255 - 8 =
8 (2^252 - 1) with 2^252 - 1 odd, so 2^4 does not divide it and 10^8 does not
either. `maximize` returns c 10^k with k >= 8 (MAX asserts `k >= 8`), a multiple
of 10^8, so ±(2^255 - 8) never reaches IDEM through `maximize`, which is the
only way IDEM is used: `Impl.add`'s first step is `maximize`, and IDEM is needed
for its outputs. NEAR and FAR check the same inputs under either comparison:
they also return on `a % 1e8 != 0` and `b % 1e8 != 0`, which exclude
±(2^255 - 8) whichever test rejects it first.

## Equivalent mutant: MAX's lower shift bound `k >= 8` at `k >= 7`

`test/halmos/AddSubRoundOnce.halmos.t.sol`, `check_maximizeFloat`. Changing
`assert(k >= 8 && k <= 76)` to `k >= 7` changes nothing: the lemma returns for
|c| above 2^223, and the magnitude assertion after it needs |c| > floor(T10 /
10^k), which at k = 7 is floor((2^255 - 1) / 10^8), above 2^223. So no
`maximize` result with k = 7, from the implementation or from a harness
override, passes the mutant where the original rejects it; both panic on the
magnitude check. The bound states the composition's `10^8 | M` for a reader, and
`testMaximizeFloatAtTheTimesTenBound` and `testMaxRejectsAMagnitudeAtT10` pin
the magnitude bounds that imply it. Every in-domain c has k in [9, 76]: 2^223
10^8 is below T10.

## Equivalent mutant: `checkSum`'s grid-gap bound `mc >= TWO_223 / 10 + 1` at `mc >= 1`

`test/halmos/AddSubRoundOnce.halmos.t.sol`, `checkSum`, reached only from NEAR.
Weakening the last disjunct to `mc >= 1` changes nothing. The two differ only
for a result with 1 <= |c| <= 2^223 / 10 that is inexact or has F != |c| u, with
F = floor(|S| / 10^D) and |c| u <= F < (|c| + 1) u, so F < 2^223 (u at most 10).
NEAR's operands are maximized multiples of 10^8, so |A| > T10 and |Q| = |B| /
10^D. With agreeing signs F >= |A| > T10. With opposing signs and D >= 2, F >=
|A| - |Q| - 1 >= T10 - 10 T10 / 100 - 1, above 2^223. At D = 1 and D = 0 the sum
is exact (10 | B) and F = |A| - |Q| is a multiple of 10^7, so F = |c| u for u in
{1, 10}, which is the exact disjunct. No (c, t) a harness override could return
reaches the weakened disjunct where the original is false, and no `Impl.add`
result does either, so the mutant proves under halmos iff the original does. The
bound states the composition's "no grid member below 10^t lies above |c| 10^t"
for a reader.

## Equivalent mutant: MAX's digit-count filter `x >= 10 ** (j + 1)` at `>`

`test/halmos/AddSubRoundOnce.halmos.t.sol`, `check_maximizeFloat`. The mutant
also admits |c| = 10^(j + 1) at case j, which case j + 1 already checks (at j =
67 it is above 2^223, where the lemma has returned). No assertion after the
filter reads j, so the mutant checks the same inputs under the same assertions,
one of them twice, and proves iff the original does.

## Equivalent mutant: FAR's `eB > FMAX - 8` bound moved up

`test/halmos/AddSubRoundOnce.halmos.t.sol`, `check_addFar`. The lemma later
returns on `eA > FMAX - 8` with eA = eB + d and d >= 77, which every eB above
FMAX - 85 meets. So the `eB > FMAX - 8` term returns on no input the later test
lets through, and moving its bound anywhere from FMAX - 85 up, `>=` included,
changes nothing.

## Equivalent mutant: PACK's `checkPackClass` without its `hasDigits` filter

`test/halmos/PackArithmeticResult.halmos.t.sol`, `checkPackClass`. Dropping
`!LibHalmosExact.hasDigits(c, n) ||` admits no new input: `packHints(c, n)` ends
every path in `isQuotient`, whose `hasDigits` on c's scaled quotient rejects any
c without digit index n, so the lemma checks the same inputs under the same
assertions.

## Equivalent mutant: PACK's `checkPackClass` with `l` fixed at `2 ** 223 - 1`

`test/halmos/PackArithmeticResult.halmos.t.sol`, `checkPackClass`. Only c =
-2^223 changes class, from 0 to 1. There `truncGrid` sheds k = 0 digits and
computes the same (m, f), so every c still reaches `pack` exactly once under the
same assertions. Same shape as MAX's digit-count `>` entry above.

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

## Resolved by removal: `pow` carry path `excess <= 67` guard at any bound from 27 up, or dropped

`src/lib/LibDecimalFloat.sol`, `packRoundedSignificant`. The `excess <= 67`
guard, the `excess > 0` guard around it and the `revertIfPastLargestFloat` on
the rounded value that followed were removed, so these mutants have no target:
the carry path is `isPastEveryFloat(roundedCoefficient, roundedExponent)` alone.
The record of why their mutants were equivalent stays as the proof that the
removal changed nothing. The `excess > 0` guard was dead by the same argument as
the `k` below 27: the rounded coefficient is at most 1e41 in magnitude
(`roundSignificant` leaves 41 digits, or 1e41 on a carry), so at an exponent up
to `int32.max` the rounded value is at most `1e41 × 10^int32.max`, below
`(2^223 + 2) × 10^int32.max`, and `isPastEveryFloat` was already false there.
The `revertIfPastLargestFloat(roundedCoefficient, roundedExponent, input)` after
the branch ran only when `isPastEveryFloat` of the same pair was false, so it
never reverted.

Changing `excess <= 67 && isPastEveryFloat(roundedCoefficient, roundedExponent)`
to `excess <= k && ...` for any `k` from 27 up, or dropping the `excess <= 67`
term, changed nothing. `roundSignificant` returns a coefficient under 1e41
unchanged, so the rounded and unrounded pairs are then equal and both branches
check the same value: past reverts `ExponentOverflow(input)` either way, and not
past packs it either way. Otherwise the rounded coefficient is at least 1e40 (41
digits, or 1e41 on a carry), so at an excess of 28 or more the rounded value is
at least `1e68 × 10^int32.max`, past every Float, and the unrounded value is
within half a unit of the rounded one's last digit, at least
`(1e40 - 1/2) × 10^(int32.max + 28)`, past too: checking either reverts
`ExponentOverflow(input)`. At an excess of 27 a rounded coefficient from
`(2^223 + 2) / 1e27` up is past while the unrounded one can be below it, so
`k = 26` was not equivalent; `testPowCarryShedsTheUnrounded` killed it. `k = 66`
and the dropped term survived the `Pow` suite at 5096 fuzz runs before the
removal.

## Equivalent mutant: `floor` zero guard narrowed to `exponent >= 0`

`src/lib/LibDecimalFloat.sol`, `floor`. Guarding only a zero at a non-negative
exponent changes nothing: a zero at a negative exponent reaches `intFrac`, which
returns `(0, 0)` for a zero coefficient at every exponent (the whole coefficient
on one side, `0 % unit` on the other), the sign test fails, and
`packArithmeticResult(0, exponent)` is `FLOAT_ZERO` before `packLossy` looks at
the exponent. `ceil` differs: its `fraction == 0` arm returns the input bytes,
so the same narrowing there is killed.

## Equivalent mutant: `ceil` fraction sign test `fraction > 0` as `fraction >= 0`

`src/lib/LibDecimalFloat.sol`, `ceil`. The `fraction == 0` arm returns on the
line before, so at the sign test the fraction is non-zero and `>= 0` is `> 0`.

## Equivalent mutant: `powUnrounded` top-bit `break` as `continue`

`src/lib/LibDecimalFloat.sol`, `powUnrounded`'s squaring loop. `continue` jumps
to the `while` condition, `exponentBInteger >= 1`, which is false at the zero
the branch tests for, so the loop exits exactly where `break` leaves it.

## Equivalent mutant: `agreeValidateTolerances` zero from `packLossless(0, 0)`

`src/lib/LibDecimalFloat.sol`, `agreeValidateTolerances`. `packLossless(0, 0)`
returns `FLOAT_ZERO` through `packLossy`'s zero arm, byte for byte the constant.

## Equivalent mutant: `agreeValidateTolerances` zero at a non-zero exponent

`src/lib/LibDecimalFloat.sol`, `agreeValidateTolerances`. Comparing against a
zero coefficient at exponent one (`Float.wrap(bytes32(uint256(1) << 224))`)
changes nothing: `lt` and `gt` unpack both operands and compare numerically, and
a zero coefficient is zero at every exponent, as the function's NatSpec states.

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

## Equivalent mutant: `agreeWithinProportional` raised-exponent test as `!=`

`src/lib/LibDecimalFloat.sol`, `agreeWithinProportional`'s fallback. Testing
`scaledExponent != proportionalExponent + anchorExponent` in place of `>`
changes nothing: `mul` returns the exponent sum plus the count of digits it
shed, never less, for operands whose exponents are int32 (the paths that move an
exponent down are for sums below `type(int256).min`), and the one product whose
exponent is not that sum, the zero product's `(0, 0)`, is already refused by
`scaledCoefficient != 0` ahead of this test.

## Equivalent mutant: `agreeWithinProportional` spread exponent test as `<=`

`src/lib/LibDecimalFloat.sol`, `agreeWithinProportional`'s fallback. Accepting
`spreadExponent <= scaledExponent - 1` in place of `==` changes nothing: the
clause runs only after `lte(spread, scaled)` was false with a non-zero
`scaledCoefficient` at a raised exponent, which puts `scaledCoefficient` at or
above `type(int256).max / 10`. A spread two or more exponents below the limit
rescales the limit by at least `100`, past int256 (or past `compareRescale`'s
`10^76` reach), and the overflow branch ranks the limit above the spread, so
`lte` is true there and the fallback never sees such a spread.
