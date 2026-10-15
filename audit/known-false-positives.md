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
