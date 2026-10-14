# Known false positives

## Equivalent mutant: `pow10` `NEVER_PAST_EXPONENT` gate raised

`src/lib/LibDecimalFloat.sol`, `pow10`. Moving the fast-exit gate from
`NEVER_PAST_EXPONENT` up by any amount to 36 (seen as `+ 1` and `+ 5`) changes
nothing: `LibDecimalFloatImplementation.pow10` returns `(1, k)` or a coefficient
of at most `1e41`, which is never past every Float below exponent
`int32.max + 27`, so no input can tell the gate positions apart.

## Equivalent mutant: `isPastEveryFloat` `excess > 67` to `excess > 68`

`src/lib/LibDecimalFloat.sol`, `isPastEveryFloat`. At `excess == 68` the mutant
falls through to the `excess >= 0` branch, where `(2 ** 223 + 1) / 10 ** 68` is
`0`, so it computes `magnitude > 0`: the same result as `magnitude != 0`.

## Equivalent mutant: `isPastEveryFloat` `excess >= 0` to `excess > 0`

`src/lib/LibDecimalFloat.sol`, `isPastEveryFloat`. At `excess == 0` the mutant
falls through to the last branch, where `(2 ** 223 + 2) * 10 ** 0` is
`2 ** 223 + 2`, so it computes `magnitude >= 2 ** 223 + 2`: the same comparison
as `magnitude > 2 ** 223 + 1`.
