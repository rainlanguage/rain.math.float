# Known false positives

## Equivalent mutant: `pow10` `NEVER_PAST_EXPONENT` gate `+ 1`

`src/lib/LibDecimalFloat.sol`, `pow10`. Moving the fast-exit gate from
`NEVER_PAST_EXPONENT` to `NEVER_PAST_EXPONENT + 1` changes nothing:
`LibDecimalFloatImplementation.pow10` returns `(1, k)` or a coefficient of at
most about 1e41, which is never past every Float at `int32.max - 9`, so no input
can tell the two apart.
