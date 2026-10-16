# Known false positives

Mutants that survive because the mutated program agrees with the original on
every input, mutants that edit an oracle no other test reads ("Not observable"),
and mutants a later change removed ("Resolved by removal"). Each entry carries
the proof; a sampled or "no known input" argument is not one.

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

## Equivalent mutants: `boundWeiSafeSide` rearranged

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. The helper's output is
read by `testFuzzWeiFloorCeilSafeSide`, whose assertions are a function of the
bounded `(a, b, c)` alone, by `testWeiSafeSideDomainInteriorEdges`, which
asserts the bounded `b` for raw `b` in `{edge, edge + 1}` with
`a = 673998666678765994866675377175491` and in `{1e33, 1e33 + 1}` with `a = 1`,
and by `testWeiSafeSideZeroFloors` at `(0, 0, 0)`.

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
`b = 1` under both. `a > 1` and `a > 1e32` have both survived. From
`k = 673998666678765994866675377175491` up the guard skips the clamp at that
test's interior `a`, which leaves `edge + 1` unwrapped, so the test kills it.

Permuting the raw inputs at the fuzz entry's call site, for example
`boundWeiSafeSide(a, c, b)`: the helper's output set is unchanged, so the fuzz
body only runs at another point of the domain the property is proven on. The
fixed callers that reach the property through the fuzz entry are
`testFuzzWeiFloorCeilSafeSideBoundsCounterexample`, which passes both orders;
`testWeiSafeSideDomainReachesBound` checks its edge through
`checkWeiFloorCeilSafeSide` directly, past the call site.

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

## Not observable: a test's own fixed input rewritten

Any test file. A test's fixed input is part of its oracle: it is the point the
test checks. A mutant that only rewrites such an input, a literal or local
argument that a test function nothing else calls passes to a check helper or to
a fuzz body, changes no line any other test reads. The file passes iff every
test passes, so every other test keeps its verdict and only the edited test can
observe the rewrite: if it fails there the mutant is killed, and if the called
check passes on the new input no test can kill it, because the rewrite is to the
oracle itself. The class is every such rewrite, not only the two that have
survived, both in `test/src/lib/LibDecimalFloat.consumerHazards.t.sol`:
`testWeiSafeSideDomainReachesBound` calling
`checkWeiFloorCeilSafeSide(a, b - 1, 7)`, a point inside the domain the property
is proven on, and `testMarginInvChainUpperBoundAttained` calling
`this.testFuzzMarginInvChain(1e66, 999)`, which the fuzz body bounds into its
proven domain. A rewrite of a line another test reads is outside this entry. In
that file `boundWeiSafeSide`, `checkWeiFloorCeilSafeSide`, `invChainProduct`,
`weiCeilUndershootInputs` and the fuzz bodies that pinned tests call are shared,
so a change there can reach another test's verdict and needs its own proof.

## Equivalent mutants: `testFuzzWeiFloorCeilSafeSide` divisor of `a / (c / b)` shrunk by an exact factor

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. With `q = a * b / c` and
`e = 10 / int224.max`, `fa.div(fc.div(fb))` truncates the divisor `c / b` by
under `e` of it, which raises the quotient, then truncates the quotient by under
`e` of it. The property holds when the result is strictly between `q - 1 / c`
and `q + 1 / c`: a non-integer `q` is at least `1 / c` from both neighbouring
integers, and an integer `q` only needs the result within 1 of it. An exact
extra factor `1 - d` on the divisor, `d` at least 0, only raises the result
further, to under `q / ((1 - e)(1 - d))`, which stays under `q + 1 / c` while
`a * b × (e + d) <= (1 - e)(1 - d)`, since each truncation is strictly under
`e`. With `a * b` at most `int224.max / 20`, `a * b × e` is at most 1/2, so
every `d` up to `(1/2 - e) / (int224.max / 20 + 1)`, about 7.4e-67, is in the
class, not only `1 - 1e-67`, which has survived and raises the result by under
0.07 / c. The lower side is unchanged: the final truncation leaves the result
above `q (1 - e)`, which is at least `q - 1 / (2c)`. A factor applied through a
`mul` or `div` that itself rounds truncates the divisor a second time by up to
`e`, which with the first already spends the whole `1 / c` at
`a * b = int224.max / 20`, so it is outside this entry.

## Equivalent mutant: `testSingleDivSubUlpFractionReadsLossless` divisor written as `packLossless(70, -1)`

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. `packLossless(7, 0)` and
`packLossless(70, -1)` are the same value. SPEC.md defines `div` as the exact
quotient rounded once toward zero to a Float, a function of the operands' values
alone, and `toFixedDecimalLossy` reads only the value of its input, so `got` and
`lossless` are the same under both for every dividend. The same holds for any
operand literal in this file rewritten to an equal value, such as
`packLossless(2, 0)` as `packLossless(20, -1)` in
`testMarginFailsAtExponentFloor`: SPEC.md defines every operation here as a
function of its operands' values alone. It holds too for an operation rewritten
to the one SPEC.md defines it as: `.inv()` in `invChainProduct` as
`packLossless(1, 0).div(...)`, since SPEC.md defines `inv(f)` as `div(1, f)`.

## Equivalent mutant: `testMarginScalesThroughLaterMul` ulp margin without the `1 / 7` term

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. The test takes no input.
Its ulp margin is `1e-67` (one ulp of `1 / 7`, exponent -67) plus `1` (one ulp
of the result, exponent 0). The result's coefficient has 68 digits at exponent
0, so `res.add(margin)` truncates toward zero at exponent 0 and drops the
`1e-67` whether or not it is in the margin: `res + 1` and `res + 1 + 1e-67` pack
to the same Float. The assertion reads only that Float, so it reaches the same
verdict under both. The term stays because the README wording it refutes names
it.

## Equivalent mutant: `testMarginRelativeToResultFailsUnderCancellation` `subtrahend` inlined

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. The test takes no input.
Replacing `.sub(subtrahend)`, where `subtrahend` is `quotient - 1000`, with
`.sub(quotient).add(1000)` at both uses changes nothing: `product`, `quotient`
and the margined product are integers of at most 68 digits (the test asserts the
first two; the margined product's 68 integer digits fill the coefficient, so its
`add` drops the margin's fraction and packs an integer), and every difference
and sum here is a small integer, so each `sub` and `add` is exact and
`a - (q - 1000)` equals `(a - q) + 1000`: 996 for `res` and 1022 for the
margined product under both programs. `eq` and `toFixedDecimalLossy` read values
alone.

## Equivalent mutant: `testFuzzMarginPerOperationPositiveChain` chain length fixed at 2

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. Replacing
`opCount = operands.length - 1` with `opCount = 2` (or 1) runs a shorter chain
on the same operands and reads `opCount` consistently in the loop, the margin
and `marginFloor`; the NatSpec's two bounds hold for every chain length whose
tracked `numerator * (opCount + 1)` stays under 2^256, so the test passes on
every input under both programs. The variant only stops the fuzz test exercising
a third op, leaving `operands[3]` unread. No other test reads the line.

## Equivalent mutant: `testFuzzMarginPerOperationPositiveChain` margin scaled in two steps

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. Computing the margin as
`acc.div(1e66).mul(opCount + 1)` instead of `acc.mul((opCount + 1)e-66)` changes
nothing: SPEC.md rounds each `div` and `mul` result once toward zero to a Float,
and `acc / 1e66` is a Float (the same coefficient at an exponent 66 lower, far
from int32.min here), so the `div` is exact and the `mul` then rounds the exact
product `(opCount + 1) × acc × 1e-66` once toward zero, the Float the original's
single `mul` returns. `add` and `toFixedDecimalLossy` read values alone, so
`ceilGot` is the same on every input. `acc.mul(1e-66).mul(opCount + 1)` and the
`(opCount + 1)` step first are equivalent by the same argument: scaling a Float
by a power of ten is exact away from the exponent limits, so the one inexact
step rounds the same digits in every order.

## Equivalent mutants: `testFuzzMarginPerOperationPositiveChain` and `testFuzzMarginInvChain` domain moved

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. The class is every move of
a bound that keeps the proof's hypotheses, not only the variants named here.
`testFuzzMarginPerOperationPositiveChain`'s assertions are a function of the
bounded operands alone, and the property is proven for every chain the bounds
admit: operands that are exact Floats (positive integers at most int224.max), a
tracked `numerator * (opCount + 1)` under 2^256, and each op's loss under 10 /
int224.max of its result. Moving the first operand's bounds anywhere within
`[1, 1e67]`, or the others' within `[1, 1e3]`, keeps every hypothesis, so the
test passes on every input under both programs; the first operand moved to
`[1e60, 1e61]` has survived. The first operand is kept in `[1e66, 1e67]` because
below the wei grid of a 68-digit Float no loss or margin reaches a wei: the
margin variants (no margin, 1e-66 once, an order or six too large, the floor as
oracle) all survive such a shrink, which reaches the same verdict as the
original and only stops the test observing the rule.

`testFuzzMarginInvChain` is the same proof at `n = 2` on `a × inv(d)`, and its
tight upper bound needs one more hypothesis: every admitted `a / d` is at least
int224.max / 10 (about 1.35e66), so the margined Float, which is above `a / d`,
is an integer (a Float above int224.max / 10 has a non-negative exponent). Any
move of its bounds that keeps `a` an exact Float, `numerator * 3` under 2^256
and the smallest `a` over the largest `d` at least int224.max / 10 (today 1e70 /
1e3 = 1e67) passes on every input, and `testMarginInvCountsItsOwnAdd`'s and
`testMarginInvChainUpperBoundAttained`'s calls into it pass on the moved domain
too. So `bound(divisor, 2, 1e3)` from 1, which adds `d = 1` where `inv(1)` and
the `mul` are exact, a lower divisor ceiling, a higher numerator floor, and a
scale of `1e5` up to `1e9` instead of `1e4` are all in the class: the last keeps
`numerator * 3` at most 3e76, under 2^256, and from `1e10` it overflows for
every numerator above about 3.9e76, and the test reverts there. A move that
admits an `a / d` below int224.max / 10 is outside this entry: without the
`* 1e4`, or with the numerator moved to `[1e60, 1e61]`, the call at
`(1e66, 1000)` in `testMarginInvChainUpperBoundAttained` has an integer `a / d`
under 3.3e65, where `marginFloor` is 0 and the margined Float is above `a / d`
with a fraction, so `ceilGot` is `a / d + 1` against a bound of `a / d`.

## Equivalent mutants: `testFuzzMarginPerOperationPositiveChain` and `testFuzzMarginInvChain` oracle weakened or draw narrowed

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`.
`testFuzzMarginPerOperationPositiveChain` asserts
`exactCeil <= ceilGot <= exactCeil + marginFloor + 1` on the chain it ran, where
`ceilGot` is the ceiling of the Float the margin's `add` returns (`got` when
`lossless`, else `got + 1`). Its NatSpec proves two facts for every chain the
bounds admit: that Float is strictly above the exact value, and at most
`exact (1 + (n + 1)e-66)`. `testFuzzMarginInvChain` proves the same of
`a × inv(d)` at `n = 2` and asserts the tight form
`exactCeil <= ceilGot <= exactCeil + marginFloor`: `a / d` is at least 1e67, so
the product `acc` and the margined Float `F` are above int224.max / 10 and so
integers; `acc` is at most `a / d`, so at most `floor(a / d)`, and the margin is
at most `m = 3e-66 × a / d`, so `ceilGot = F <= floor(a / d) + floor(m)`, with
`marginFloor = floor(m)`. Each variant below passes on every input, so it
reaches the original's verdict everywhere.

Any raise of an `assertLe` bound, or lowering of an `assertGe` bound, in this
file's fuzz tests is in this class, not only the variants named here: the
original inequality holds on every admitted input (the proofs in the tests'
NatSpec), so a weaker one does too, and the verdict can change only if computing
the moved bound reverts. It does not revert while every intermediate stays under
2^256 and at least 0. `numerator` is at most 1e76 in the positive chain (three
muls of 1e3 on 1e67) and 1e71 in the inv chain, so a raise added after the
divisions (`+ 1`, `marginFloor * 10`, the whole bound times 10) never reverts,
nor does a factor up to 3e5 on the inv chain's `numerator * 3`; a further factor
`k` above 2 on the positive chain's `numerator * (opCount + 1)` overflows at a
numerator above 2^256 / 4k (about 2.9e75 at `k = 10`), which a three-mul chain
reaches, and is outside this entry. Variants that have survived:
`testFuzzMarginInvChain`'s `numerator * 3 / 1e66 / divisor` as `numerator * 4`
or `numerator * 30` (at most 3e72), and its tight bound with a `+ 1`.

`testFuzzMarginInvChain`'s `(numerator + divisor - 1) / divisor` as
`numerator / divisor`, the floor of `a / d`: `ceilGot` is `F`, an integer above
`a / d` and so above the floor, and `F <= floor(a / d) + floor(m)` (above) is
the mutant's upper bound.

`% 3` changed to `% 2` in the op draw: `op` is then 0 or 1, so the chain is
drawn from `mul` and `div` only. Every chain the mutant runs is one the original
runs for the `ops` whose two-bit fields are 0 and 1, and the property is proven
for every chain the bounds admit, so both pass on every input. The variant only
stops the fuzz test exercising `add`; `testMarginCountsAdds` and
`testMarginCountsItsOwnAdd` pin it. Reading the draw from the next two bits,
`ops >> (2 * i)`, is the same class: every chain it runs is one the original
runs for another `ops`.

`exactCeil` as `numerator / denominator + 1`: the ceiling unless the exact value
is an integer, where it is one above it. The Float is strictly above the exact
value, so when that is the integer `exact` the Float is an integer of at least
`exact + 1` or a non-integer above `exact`, and `ceilGot` is at least
`exact + 1` either way. The upper bound only loosens.

`marginFloor` from `opCount + 2` instead of `opCount + 1`: read only by the
upper bound, which it loosens; `numerator × 5` is under 2^256 (the numerator is
at most 1e76), so nothing reverts.

`testFuzzMarginPerOperationPositiveChain`'s `ceilGot` as `got + 1` whether or
not `lossless`: differs only when the Float is an integer `F`, where the
original reads `F` and the mutant `F + 1`. The lower bound holds a fortiori. For
the upper bound, `F <= exact + m` with `m = (n + 1)e-66 × exact` and
`marginFloor = floor(m)`: if `exact` is an integer, `F - exact` is an integer at
most `m`, so at most `floor(m)`; otherwise
`F <= floor(exact + m) <= floor(exact) + floor(m) + 1 = ceil(exact) + floor(m)`.
So `F + 1 <= exactCeil + marginFloor + 1`. The same variant in
`testFuzzMarginInvChain` is outside this entry: its bound has no `+ 1`, and
`testMarginInvChainUpperBoundAttained` reaches it with an integer `F`.

Margin of `n e-66` instead of `(n + 1)e-66`: the chain length `opCount` is 3, so
the margin is `3e-66` of the result against a loss under `4 × 10 / int224.max`,
about 2.968e-66, of it (three ops and the margin's `add`; the margin's `mul`
truncates only the margin), and `(1 - 7.42e-67)^4 (1 + 3e-66 (1 - 7.42e-67))`
still exceeds 1, so the Float stays strictly above the exact value and the lower
bound holds. A smaller margin can only lower the Float, so the upper bound holds
too. `n e-66` falls short of `(n + 1) × 7.42e-67` only at `n <= 2`;
`testMarginCountsItsOwnAdd` pins that at `n = 2`, where `2e-66` leaves the
lossless-flag ceiling one short. Fuzzing the chain length over 1..3 does not
observe it: a shortfall needs every truncation near its maximum at once, and
5096 runs at seeds 0 and 1 pass under the variant.

## Equivalent mutants: `testFuzzMarginPerOperationPositiveChain` and `testFuzzMarginInvChain` margin lowered or an exact factor added, within the proven loss

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. With `e = 10 / int224.max`
(about 7.4184e-67), each truncating op leaves its result above `1 - e` of the
exact result of that op on its computed operands. The chain has `t` truncations
that reach the result: its ops and the margin's `add`, 4 in the positive chain
and 3 in the inv chain (the margin's own `mul` truncates only the margin, by the
factor `1 - e`). A margin `m` of the result and exact extra factors `1 - d_i`,
each `d_i` at least 0, anywhere in the chain leave the margined Float above
`exact × (1 - e)^t × (1 - d_1) × ... × (1 - d_k) × (1 + m (1 - e))`. While that
product is at least 1 the Float stays strictly above the exact value and the
lower bound holds; a margin at most the test's own and factors at most 1 only
lower the Float, so the upper bound holds too. Every such variant passes on
every input, so the class is all of them, not only the variants named here:

- The margin lowered to any `m` from the proven loss up to the test's own: from
  2.968e-66 in the positive chain (whose margin is 4e-66) and from 2.226e-66 in
  the inv chain (3e-66). The positive chain at 3.6e-66 and the inv chain at
  2.7e-66 have survived. A margin below the proven loss is outside this entry:
  2e-66 in the inv chain fails on the input `testMarginInvCountsItsOwnAdd` pins,
  and no margin or 1e-66 once fail on the wei grid. A margin above the test's
  own is outside it too: in the inv chain, 3.1e-66 or more fails
  `testMarginInvChainUpperBoundAttained`.
- An exact extra factor `1 - d` on chain ops while the product stays at least 1:
  `1 - 1e-67` on each of the positive chain's three ops leaves it about 1 +
  7.3e-67 at the 4e-66 margin, and has survived. A factor applied through a
  `mul` or `div` that itself rounds adds that op's truncation to `t`; three such
  factors take the product to about 1 - 1.5e-66, so they are outside this entry.

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
