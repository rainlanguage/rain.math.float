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

## Equivalent mutants: `LibHalmosExact` hint filters and `eqValue` gap cutoff

`test/halmos/LibHalmosExact.sol`. The hint filters (`maximizeHints`,
`packHints`) are true for every input in their domain
(`test/halmos/LibHalmosExact.t.sol` and the `hints`/`pack-hints` halmos lemmas
prove it), so a change that keeps every call inside that domain leaves the
boolean unchanged. Such a change only moves which terms the halmos branch solver
is handed a fact for, which the filters' NatSpec names as costing completeness
(a loop-bound warning or extra paths), never soundness; the `quick` lemma run
proving MAX without a warning is what pins the picks, not a forge test.

- `maximizeHints`: `if (j >= 75)` to `if (j >= 76)`. For j = 75, |c| is in
  [1e75, 1e76), so each `shiftHint(c, 0, 75, t)` for t in {38, 57, 66, 74, 75}
  compares a nonzero quotient against a false `s + j < t` and is true, every
  `s + j < t` guard is false so s stays 0, the loop breaks at once, and the
  final call is `timesTenHint(c, 0, 75)`, the original's return value.
- `maximizeHints`: `s += 38` to `s += 37`. Every later shift still keeps s + j
  below 76 (37 leaves it below 75; 19, 10, the twos and the one each fire only
  while s + j is below their threshold of at most 75), so every `shiftHint` and
  the final `timesTenHint` stay in the domain where they are true.
- `packHints`: `while (m >= 67)` to `while (m > 67)`. Every
  `isQuotient(c, x,
  n, m)` the function visits is true by construction (x is c
  cut by n - m digits with m its digit count), so returning it at m = 67 instead
  of entering the loop body, which either returns true or steps to m = 66 and
  returns the same true, gives the same boolean.
- `hasDigits`: dropping `c != 0 &&`. For c = 0, `x >= 10 ** j` is false for
  every j (10^j is at least 1); for c nonzero the term is true. Same result on
  every input.
- `eqValue`: `if (d > 77) return false` to `if (d > 76)` in the `re >= se`
  branch. At d = 77 the original computes `r * 10^77 == s` with r at least 1,
  and 10^77 exceeds 2^255, so no int256 magnitude s equals it: false either way.
  The `re < se` branch's `d > 77` is not probed separately; the proof is the
  same.
