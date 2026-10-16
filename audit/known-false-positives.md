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

## Equivalent mutants: `boundWeiSafeSide` rearranged

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. The helper's output is
read by `testFuzzWeiFloorCeilSafeSide`, whose assertions are a function of the
bounded `(a, b, c)` alone, by `testWeiSafeSideDomainInteriorEdges`, which
asserts the bounded `b` for raw `b` in `{edge, edge + 1}` with `a = 8e32` and in
`{1e33, 1e33 + 1}` with `a = 1`, and by `testWeiSafeSideZeroFloors` at
`(0, 0, 0)`.

Moving the clamp before `b = bound(b, 1, 1e33)`: both orders land `b` in
`[1, min(X, 1e33)]` for `X = WEI_SAFE_SIDE_AB_MAX / a`, because whichever bound
runs second is the identity on a value already inside its interval. The orders
agree exactly for every raw `b` at most 1e33: there the first bound of the
original is the identity, and the mutant's second bound is the identity on the
clamp's output. They also agree for every raw `b` at most `X` when `X` is at
least 1e33: the clamp is then the identity in both orders, and only
`bound(b, 1, 1e33)` acts. They differ only for a raw `b` above both 1e33 and
`X`, where the original wraps into `[1, 1e33]` before clamping and the mutant
clamps first. Every input then reaches the same verdict: the fuzz property holds
on the whole interval (the proof in the fuzz test's NatSpec), and no fixed input
is above both: the raw `b` values
`testFuzzWeiFloorCeilSafeSideBoundsCounterexample` passes, in either order, are
at most 1e33, and the one raw `b` above 1e33 in
`testWeiSafeSideDomainInteriorEdges`, `1e33 + 1`, is passed with `a = 1`, where
`X = WEI_SAFE_SIDE_AB_MAX`.

Raising the guard from `a > 0` to `a > 1`, or to any `a > k` with `k` at most
`WEI_SAFE_SIDE_AB_MAX / 1e33` (about 6.7e32): the branch differs only for
`0 < a <= k`, where the skipped clamp is `bound(b, 1, WEI_SAFE_SIDE_AB_MAX / a)`
with a limit of at least 1e33, the identity on a `b` already in `[1, 1e33]`. The
helper's output is the same for every input;
`testWeiSafeSideDomainInteriorEdges` passes `a = 1` and sees `b = 1e33` and
`b = 1` under both.

## Equivalent mutants: `testFuzzWeiFloorCeilSafeSideBoundsCounterexample` drops calls

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. The loop makes two calls
per pinned input, `(a, b, c)` and `(a, c, b)`. Any change that only removes
calls leaves every verdict unchanged: skipping any pinned input or any proper
subset of them (`i = 1`, `i + 1 < inputs.length`, and the like), or rewriting
one call into a copy of the other, which removes that call's argument order. The
test takes no input and passes iff every call passes, and each call passes
because `boundWeiSafeSide` wraps any triple into the domain on which the fuzz
property is proven, so any subset of the calls reaches the same verdict. Such a
change deletes a check, the class no test can kill because the tests are the
oracle. Each skipped input's undershoot stays asserted by its own pinned test.

## Equivalent mutant: `testWeiSafeSideDomainInteriorEdges` interior `a` moved (9e32)

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. The test takes no input
and derives `edge = WEI_SAFE_SIDE_AB_MAX / a` from its `a`, so replacing
`a = 8e32` with any `a` from 673998666678765994866675377175491, the smallest
with `edge < 1e33`, up to 1e33 checks the clamp at another interior point and
reaches the same verdict: `edge` and `edge + 1` are at most 1e33, so
`bound(b, 1, 1e33)` leaves both alone, and the clamp returns `edge` and wraps
`edge + 1` to 1. The `a = 1` and `a = 1e33` calls do not read `a`. Below
673998666678765994866675377175491 `edge` reaches 1e33 and `assertLt(edge, 1e33)`
fails, so a smaller `a` is killed, not equivalent.

## Equivalent mutant: `testSingleDivSubUlpFractionReadsLossless` divisor written as `packLossless(70, -1)`

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. `packLossless(7, 0)` and
`packLossless(70, -1)` are the same value. SPEC.md defines `div` as the exact
quotient rounded once toward zero to a Float, a function of the operands' values
alone, and `toFixedDecimalLossy` reads only the value of its input, so `got` and
`lossless` are the same under both for every dividend.

## Equivalent mutant: `testMarginScalesThroughLaterMul` ulp margin without the `1 / 7` term

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. The test takes no input.
Its ulp margin is `1e-67` (one ulp of `1 / 7`, exponent -67) plus `1` (one ulp
of the result, exponent 0). The result's coefficient has 68 digits at exponent
0, so `res.add(margin)` truncates toward zero at exponent 0 and drops the
`1e-67` whether or not it is in the margin: `res + 1` and `res + 1 + 1e-67` pack
to the same Float. The assertion reads only that Float, so it reaches the same
verdict under both. The term stays because the README wording it refutes names
it.

## Equivalent mutants: `testFuzzMarginPerOperationPositiveChain` domain moved

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. The assertions are a
function of the bounded operands alone, and the property is proven for every
chain the bounds admit: operands that are exact Floats (positive integers at
most int224.max), a tracked `numerator * (n + 1)` under 2^256, and each op's
loss under 10 / int224.max of its result. Moving the first operand's bounds
anywhere within `[1, 1e67]`, or the others' within `[1, 1e3]`, keeps every
hypothesis, so the test passes on every input under both programs. The first
operand is kept at 67 digits because below the wei grid of a 68-digit Float no
loss or margin reaches a wei: the margin variants of the round-10 scan (no
margin, 1e-66 once, an order or six too large, the floor as oracle) all survive
such a shrink, which reaches the same verdict as the original and only stops the
test observing the rule.

## Equivalent mutants: `testFuzzMarginPerOperationPositiveChain` oracle weakened or draw narrowed

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. The test asserts
`exactCeil <= ceilGot <= exactCeil + marginFloor + 1` on the chain it ran, where
`ceilGot` is the ceiling of the Float the margin's `add` returns (`got` when
`lossless`, else `got + 1`). Its NatSpec proves two facts for every chain the
bounds admit: that Float is strictly above the exact value, and at most
`exact (1 + (n + 1)e-66)`. Each variant below passes on every input, so it
reaches the original's verdict everywhere.

`% 3` changed to `% 2` in the op draw: `op` is then 0 or 1, so the chain is
drawn from `mul` and `div` only. Every chain the mutant runs is one the original
runs for the `ops` whose two-bit fields are 0 and 1, and the property is proven
for every chain the bounds admit, so both pass on every input. The variant only
stops the fuzz test exercising `add`; `testMarginCountsAdds` and
`testMarginCountsItsOwnAdd` pin it.

`exactCeil` as `numerator / denominator + 1`: the ceiling unless the exact value
is an integer, where it is one above it. The Float is strictly above the exact
value, so when that is the integer `exact` the Float is an integer of at least
`exact + 1` or a non-integer above `exact`, and `ceilGot` is at least
`exact + 1` either way. The upper bound only loosens.

`marginFloor` from `n + 2` instead of `n + 1`: read only by the upper bound,
which it loosens; `numerator × 5` is under 2^256 (the numerator is at most
1e76), so nothing reverts.

`ceilGot` as `got + 1` whether or not `lossless`: differs only when the Float is
an integer `F`, where the original reads `F` and the mutant `F + 1`. The lower
bound holds a fortiori. For the upper bound, `F <= exact + m` with
`m = (n + 1)e-66 × exact` and `marginFloor = floor(m)`: if `exact` is an
integer, `F - exact` is an integer at most `m`, so at most `floor(m)`; otherwise
`F <= floor(exact + m) <= floor(exact) + floor(m) + 1 = ceil(exact) + floor(m)`.
So `F + 1 <= exactCeil + marginFloor + 1`.

Margin of `n e-66` instead of `(n + 1)e-66`: `n` is fixed at 3, so the margin is
`3e-66` of the result against a loss under `4 × 10 / int224.max`, about
2.968e-66, of it (three ops and the margin's `add`; the margin's `mul` truncates
only the margin), and `(1 - 7.42e-67)^4 (1 + 3e-66 (1 - 7.42e-67))` still
exceeds 1, so the Float stays strictly above the exact value and the lower bound
holds. A smaller margin can only lower the Float, so the upper bound holds too.
`n e-66` falls short of `(n + 1) × 7.42e-67` only at `n <= 2`;
`testMarginCountsItsOwnAdd` pins that at `n = 2`, where `2e-66` leaves the
lossless-flag ceiling one short. Fuzzing the chain length over 1..3 does not
observe it: a shortfall needs every truncation near its maximum at once, and
5096 runs at seeds 0 and 1 pass under the variant.

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
