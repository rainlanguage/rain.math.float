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

## Equivalent mutants: `WEI_SAFE_SIDE_AB_MAX` divisor raised (21, 40)

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. Raising the divisor from
20 to any `d` from 21 up to `int224.max / 1e33` (about 1.3e34), of which 21 and
40 are probed, shrinks the constant, and every test reaches the same verdict on
every input under both values. `testFuzzWeiFloorCeilSafeSide` asserts a property
its NatSpec proves for every `a * b <= int224.max / 20`, so it holds on the
subset `a * b <= int224.max / d` the mutant fuzzes, and the swapped-order calls
in `testFuzzWeiFloorCeilSafeSideBoundsCounterexample` wrap into that subset too.
`testWeiSafeSideDomainInteriorEdges` reads the constant it checks the clamp
against, so its edges move with it, and its fixed inputs stay inside the domain
while `WEI_SAFE_SIDE_AB_MAX >= 1e33`: that keeps `b = 1e33` passing through at
`a = 1` and the clamp limit at least 1 for every `a` up to 1e33. Past
`int224.max / 1e33` that assertion fails, so a larger `d` is killed, not
equivalent. Every pinned counterexample has `a * b` of at least 0.0510
int224.max, above the constant for every `d >= 20`, so each
`assertGt(a * b, WEI_SAFE_SIDE_AB_MAX)` passes, and their upper bounds are
literals. Divisors below 20 are not equivalent: 19 and 16 are killed by
`testWeiCeilUndershootNearBound` (0.0510 int224.max), 15 by
`testWeiCeilUndershootInsideFifteenth` (0.0630), 14 and 10 by the other pinned
inputs.

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
