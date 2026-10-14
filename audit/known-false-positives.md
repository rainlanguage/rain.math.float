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
