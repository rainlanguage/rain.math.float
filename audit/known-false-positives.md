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

## Equivalent mutants: `LibHalmosExact` hint filters, `hasDigits`, `abs`, `eqValue` and the slice defaults

`test/halmos/LibHalmosExact.sol`.

The hint filters (`divHint`, `shiftHint`, `timesTenHint`, `maximizeHints`,
`packHints`) are true for every input in their domain, and being true is the
only property forge observes of them (`test/halmos/LibHalmosExact.t.sol` asserts
it; the `divhint`, `hints` and `hints-pack` halmos lemmas prove it). So any
mutant of a hint filter that keeps it true on its domain is equivalent under
forge, `return true` included: a dropped conjunct (`c / 1e72`, the int224 early
return, an `isQuotient`), a moved threshold (`j >= 76`, `while (m > 67)`,
`>= 74`), a changed step (`+= 37`, `+= 39`, `+= 20`, `+= 11`, `+= 3`, `+= 2`;
those reaching s + j = 76 with s > 0 wrap the shifted product, and a wrapped
product is still outside [-T10, T10] and nonzero divided by 10^t), or `T10` as
`int256.max / 11` (`timesTenHint` is an identity for any constant at most
int256.max). Such a change only moves which terms the halmos branch solver is
handed a fact for, which the filters' NatSpec names as costing completeness (a
loop-bound warning or extra paths), never soundness; a lemma run proving without
a warning is what pins the picks, not a forge test.

- `hasDigits`: dropping `c != 0 &&`. For c = 0, `x >= 10 ** j` is false for
  every j (10^j is at least 1); for c nonzero the term is true.
- `abs`: `x < 0` to `x <= 0`. Only x = 0 changes branch, and -0 is 0.
- `inSlice`, `overlapsSlice`: the `envOr` defaults with the env unset.
  `testSlices` pins the defaults [0, uint256.max] through empty variables, which
  `envOr` reads as unset; a mutant that survives it keeps them. Every lemma that
  calls them is sliced in the matrix and runs with both set.
- `eqValue`: `&&` for the zero test's `||`. With exactly one coefficient zero
  the sign test passes only for a positive other, where the product test
  compares zero against a nonzero product under its overflow guard: false, as
  the original.
- `eqValue`: `re > se` for `re >= se`. At re = se both branches have d = 0, p =
  1 and compare r with s.
- `eqValue`: `d > 76` or `d > 78` for `d > 77`, either branch. At d = 77 the
  product is at least 10^77 > 2^255, above every magnitude. At d = 78 the
  wrapped `10 ** 78` exceeds 2^255, so `max / p` is 1 and the product test needs
  a magnitude of p: false either way.
- `eqValue`: `<` for the overflow guard's `<=`, either branch. At r = floor(max
  / p) the product r p is above 2^256 - 1 - p > 2^255 for d <= 76 and is 10^77 >
  2^255 for d = 77, above every magnitude, so the equality is false with the
  guard either way.

## Equivalent mutants: the parser's `NEVER_PAST_EXPONENT` gates before `isPastEveryFloat`

`src/lib/parse/LibParseDecimalFloat.sol`, `parseDecimalFloatInline` and
`parseDecimalFloatPastInt256`, the
`exponent > LibDecimalFloat.NEVER_PAST_EXPONENT &&` operand before each
`LibDecimalFloat.isPastEveryFloat` call. Changing either gate to `>=`, or
dropping it, changes nothing: the first statement of `isPastEveryFloat` is
`if (exponent <= NEVER_PAST_EXPONENT) return false;`, so the gate repeats the
callee's own short-circuit. Wherever the original gate is false the mutant calls
the function and gets `false`, the same value the original's `&&` produced, and
wherever the gate is true the two are the same expression. The gate only saves
the call on the hot path. Moving it the other way, to
`> NEVER_PAST_EXPONENT + 1`, is not equivalent, and
`testParseOverflowThresholdExcesses`,
`testParsePastInt256FirstExponentPastNeverPast` and
`testParsePastInt256GateAtNeverPastExponentPlusOne` kill it.
