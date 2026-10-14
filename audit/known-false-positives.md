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

## Equivalent mutants: `WEI_SAFE_SIDE_AB_MAX` divisor tightened

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. Changing the divisor from
20 to 40 shrinks the fuzz domain to one where the property still holds, and 20
to 15 (0.0667 of int224.max) stays below the smallest known failing input at
0.0701 of int224.max, so no known input distinguishes either from the original.

## Equivalent mutants: `testFuzzWeiFloorCeilSafeSide` clamp rearranged

`test/src/lib/LibDecimalFloat.consumerHazards.t.sol`. The assertions read only
the bounded `a`, `b` and `c`, and the clamp exists to keep `a * b` at or below
`WEI_SAFE_SIDE_AB_MAX`. These rewrites keep that domain exactly.

Moving the clamp before `b = bound(b, 1, 1e33)`: both orders land `b` in
`[1, min(X, 1e33)]` for `X = WEI_SAFE_SIDE_AB_MAX / a`. Bounding into `[1, X]`
then `[1, 1e33]` is a no-op on the second step when `X <= 1e33` and on the first
when `X > 1e33`, and the same holds with the steps swapped. A raw `b` can map to
a different point of that interval, but the property holds across all of it, so
every input passes under both.

Clamping `a` instead, as `a = bound(a, 1, WEI_SAFE_SIDE_AB_MAX / b)`: for every
`b` in `[1, 1e33]` the divisor is at least `WEI_SAFE_SIDE_AB_MAX / 1e33 > 1`, so
the domain is again every `(a, b)` with `a <= 1e33`, `1 <= b <= 1e33` and
`a * b <= WEI_SAFE_SIDE_AB_MAX`, plus `a = 0`. The pinned callers
`testFuzzWeiFloorCeilSafeSideBoundsCounterexample` and
`testFuzzWeiFloorCeilSafeSideClampWrapsToOne` wrap into that domain under both
clamps. A test that told either mutant apart would need the property to fail
inside the domain the test asserts it on.

Raising the guard from `a > 0` to `a > 1`, or to any `a > k` with `k` at most
`WEI_SAFE_SIDE_AB_MAX / 1e33` (about 6.7e32): for every such `a` the clamp's
limit `WEI_SAFE_SIDE_AB_MAX / a` is at least 1e33, which `b` already satisfies,
so the clamp it skips is a no-op and no bounded input changes.
