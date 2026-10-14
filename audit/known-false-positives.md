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

## Equivalent mutants: `WEI_SAFE_SIDE_AB_MAX` divisor raised (21, 40)

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. Raising the divisor from
20 to any `d` from 21 up to `int224.max / 2e33` (about 6.7e33), of which 21 and
40 are probed, shrinks the constant, and every test reaches the same verdict on
every input under both values. `testFuzzWeiFloorCeilSafeSide` asserts a property
its NatSpec proves for every `a * b <= int224.max / 20`, so it holds on the
subset `a * b <= int224.max / d` the mutant fuzzes. `testWeiSafeSideClampEdges`
and `testWeiSafeSideDomainInteriorEdges` read the constant they check the clamp
against, so their edges move with it, and their fixed inputs stay inside the
domain while `WEI_SAFE_SIDE_AB_MAX / 1e33 >= 2`: that keeps `b = 2` passing
through at `a = 1e33` and `b = 1e33` passing through at `a = 1`. Past
`int224.max / 2e33` those assertions fail, so a larger `d` is killed, not
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
bounded `(a, b, c)` alone, by `testWeiSafeSideClampEdges`, which asserts the
bounded `b` for raw `b` in `{edge + 1, edge, 1, 2}` with `a = 1e33`, by
`testWeiSafeSideDomainInteriorEdges`, which asserts it for raw `b` in
`{edge, edge + 1}` with `a = 8e32` and in `{1e33, 1e33 + 1}` with `a = 1`, and
by `testWeiSafeSideZeroFloors` at `(0, 0, 0)`.

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
is above both: the raw `b` values of `testWeiSafeSideClampEdges` and
`testFuzzWeiFloorCeilSafeSideBoundsCounterexample` are at most 1e33, and the one
raw `b` above 1e33 in `testWeiSafeSideDomainInteriorEdges`, `1e33 + 1`, is
passed with `a = 1`, where `X = WEI_SAFE_SIDE_AB_MAX`.

Raising the guard from `a > 0` to `a > 1`, or to any `a > k` with `k` at most
`WEI_SAFE_SIDE_AB_MAX / 1e33` (about 6.7e32): the branch differs only for
`0 < a <= k`, where the skipped clamp is `bound(b, 1, WEI_SAFE_SIDE_AB_MAX / a)`
with a limit of at least 1e33, the identity on a `b` already in `[1, 1e33]`. The
helper's output is the same for every input;
`testWeiSafeSideDomainInteriorEdges` passes `a = 1` and sees `b = 1e33` and
`b = 1` under both.

## Equivalent mutant: `testFuzzWeiFloorCeilSafeSideBoundsCounterexample` runs one input fewer

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. Changing the loop bound
from `i < inputs.length` to `i + 1 < inputs.length` skips the last pinned input.
The test takes no input and passes iff every call passes, and each call passes
because `boundWeiSafeSide` wraps any triple into the domain on which the fuzz
property is proven, so three calls and four reach the same verdict. The test
exists so that a change to the clamp has to survive every pinned input; the
clamp mutants it kills are killed by its first input alone, and the last input's
undershoot is asserted by `testWeiCeilUndershootNearBound`. A test that told the
two apart would have to count the test's own calls, which pins plumbing, not
behaviour.
