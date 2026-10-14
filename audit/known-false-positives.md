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
