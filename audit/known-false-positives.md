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
