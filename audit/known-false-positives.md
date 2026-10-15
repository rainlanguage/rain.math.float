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

## Equivalent mutant: `floorE20` sign test at zero

`test/src/lib/implementation/LibDecimalFloatImplementation.log10Unrounded.t.sol`,
the log10 test oracle's `floorE20`. Changing `value < 0 && value % 1e20 != 0` to
`value <= 0 && value % 1e20 != 0` changes the first conjunct only at
`value == 0`, where `0 % 1e20` is `0`, so the second conjunct is false and the
conjunction is false under both. At every other `value`, `<` and `<=` agree.
Both return `quotient` at zero and take the same branch everywhere else, for
every int256 input.
