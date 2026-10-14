# Known false positives

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

## Equivalent mutant: `WEI_SAFE_SIDE_AB_MAX` divisor raised to 40

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. Raising the divisor from
20 to 40 halves the constant, and every test reaches the same verdict on every
input under both values. `testFuzzWeiFloorCeilSafeSide` asserts a property its
NatSpec proves for every `a * b <= int224.max / 20`, so it holds on the subset
`a * b <= int224.max / 40` the mutant fuzzes. `testWeiSafeSideClampEdges` reads
the constant it checks the clamp against, so its edges move with it. Every
pinned counterexample has `a * b` of at least 0.0510 int224.max, above both
constants, so each `assertGt(a * b, WEI_SAFE_SIDE_AB_MAX)` passes under both,
and their upper bounds are literals. Divisors below 20 are not equivalent: 19
and 16 are killed by `testWeiCeilUndershootNearBound` (0.0510 int224.max), 15 by
`testWeiCeilUndershootInsideFifteenth` (0.0630), 14 and 10 by the other pinned
inputs.

## Equivalent mutants: `boundWeiSafeSide` rearranged

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. The helper's output is
read by `testFuzzWeiFloorCeilSafeSide`, whose assertions are a function of the
bounded `(a, b, c)` alone, and by `testWeiSafeSideClampEdges`, which asserts the
bounded `b` for raw `b` in `{edge + 1, edge, 1, 2}` with `a = 1e33`.

Moving the clamp before `b = bound(b, 1, 1e33)`: both orders land `b` in
`[1, min(X, 1e33)]` for `X = WEI_SAFE_SIDE_AB_MAX / a`, because whichever bound
runs second is the identity on a value already inside its interval. The orders
agree exactly for every raw `b` at most 1e33: there the first bound of the
original is the identity, and the mutant's second bound is the identity on the
clamp's output. They differ only for a raw `b` above 1e33, which the original
wraps into `[1, 1e33]` before clamping. Every input then reaches the same
verdict: the fuzz property holds on the whole interval (the proof in the fuzz
test's NatSpec), and the raw `b` values of `testWeiSafeSideClampEdges` and
`testFuzzWeiFloorCeilSafeSideBoundsCounterexample` are all at most 1e33.

Raising the guard from `a > 0` to `a > 1`, or to any `a > k` with `k` at most
`WEI_SAFE_SIDE_AB_MAX / 1e33` (about 6.7e32): the branch differs only for
`0 < a <= k`, where the skipped clamp is `bound(b, 1, WEI_SAFE_SIDE_AB_MAX / a)`
with a limit of at least 1e33, the identity on a `b` already in `[1, 1e33]`. The
helper's output is the same for every input.
