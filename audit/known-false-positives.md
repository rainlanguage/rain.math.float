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

## Equivalent mutants: frozen `mulDiv` copy, fast path and overflow check

`test/lib/LibDecimalFloatSqrtVariants.sol`, the private `mulDiv` copied from
26a3cf06 for `sqrtPre359` and `sqrtPr309`. Both call it as
`mulDiv(coefficient, scale, root)` with `coefficient >= 1e75` after scale-up and
`scale >= 1e4`, so the product is at least `1e79 > 2^256` and `prod1` is never
zero: the `prod1 == 0` fast path is unreachable, and any change to its
`return prod0 / denominator` is equivalent (inverting the condition is not, and
is killed). The denominator is the Newton seed times `1e3` (`sqrtPre359`) or at
least `1e2` (`sqrtPr309`), at least `2^124 * 1e2 > 2e39`, so
`prod1 >= denominator` would need `coefficient * scale >= 2e39 * 2^256 > 2e116`,
while `coefficient * scale < 2^255 * 1e6 < 6e82`. The `MulDivOverflow` check
never fires on any input a baseline can pass it, and relaxing it to `>` is
equivalent.

## Equivalent mutants: frozen `maximize` copy, step gates

`test/lib/LibFormatDecimalFloatPr321.sol`, the private `maximize` copied from
ce55522. The `E38`, `E57`, `E66` steps, the `E74` loop and the `E75` step each
multiply only while the coefficient is below a gate, and no step overshoots
`1e76` because every gate times its multiplier is at most `1e76`. Lowering the
`E57` gate to `1e56` or the `E66` gate to `1e65` only skips a step for
coefficients the loop and the final `x10` step then carry to the same
`[1e75, 1e76)` value with the same exponent shift. The gates are gas
distribution, not results; the exact `LibExactFloat.maximize` oracle in
`testFrozenMaximizeOracle` agrees with both. Lowering `E74` or `E75` by a decade
is not equivalent (the loop or the last step stop short) and is killed.

## Equivalent mutant: frozen `maximizeFull` copy, shortfall check

`test/lib/LibFormatDecimalFloatPr321.sol`, `maximizeFull` is private and reached
only from `_toScientific` with the exponent `unpack` read from a Float, so the
exponent is an int32 and `maximize` shifts it by at most 76: it cannot wrap
below `type(int256).min`, so the shortfall is always zero and any test of it
that still passes zero (`!= 0` to `> 1`) is equivalent.

## Equivalent mutants: frozen `packLossy` copy in the parse baseline

`test/lib/LibParseDecimalFloatPr321.sol`, the private `packLossy` copied from
ff6d70c. It is reached only from `parseDecimalFloat`, which returns
`ParseDecimalPrecisionLoss` with `Float.wrap(0)` whenever `lossless` is false,
so the packed float of a lossy result is never observed.

- Nearest-bound value: the bound path is taken only when shedding `k` digits
  left exactly `int224.max / 10`, which needs the coefficient after `k - 1`
  sheds to be `2^223` or `2^223 + 1`; lossless would need it to be a multiple of
  ten, and `2^223` ends in 8. So that path is always lossy and its packed bound
  (`type(int224).max`, mutated to `- 1`) is discarded.
- Shortcut gate `/ 1e72` raised to `/ 1e73`: truncating division by `1e5` once
  equals division by ten five times, each raising the exponent by one, so a
  coefficient that skips the shortcut sheds the same digits in the loop.
- `initialExponent > 0` relaxed to `>= 0`: the branch is entered only when the
  exponent left int32 after shedding, which raises it by at most ten, so an
  initial exponent of zero ends in `[0, 10]` and never reaches it.
- `!fits ||` dropped from the lift guard: when the coefficient did not fit
  int224, the headroom check that follows compares the initial coefficient with
  `int224.max / scale` for `scale >= 10`, which it exceeds, and reverts with the
  same `ExponentOverflow(initialSignedCoefficient, initialExponent)`.
- `exponent <= initialExponent` relaxed to `<`: at equality the general case
  takes the coefficient modulo `10 ** 0 == 1`, which is zero, the same `true`.

## Equivalent mutant: `baselines.rs` `code_only` keeps newlines

`crates/tests/src/baselines.rs`, `code_only` blanks comments and strings to
spaces but keeps their newlines. Blanking the newlines too changes nothing the
guard reads: `use_on`, the `using` check and `without_function` search for
substrings and match braces, none of which looks at line structure.

## Equivalent mutants: frozen `scaleUp` copy, step gates

`test/lib/LibDecimalFloatSqrtVariants.sol`, the private `scaleUp` copied from
26a3cf06 for `sqrtPre359`. Its seven steps multiply by `10^s` only while the
coefficient is below `10^(76 - s)`, so no step overshoots `1e76`, and the last
step leaves it at least `1e75`. Lowering the `1e38` gate to `1e37` only makes a
coefficient in `[1e37, 1e38)` skip the `x1e38` step, after which the `x1e19`,
`x1e10`, `x1e5`, `x1e3` and `x10` steps take it to the same `[1e75, 1e76)` value
with the same 38-digit shift; lowering the `1e66` gate to `1e65` likewise sends
`[1e65, 1e66)` through `x1e5`, `x1e3` and `x1e2` for the same 10-digit shift.
The gates distribute gas, not results. Changing a step's multiplier or shift is
not equivalent and is killed.

## Equivalent mutant: frozen `maximize` copy, outer gate

`test/lib/LibFormatDecimalFloatPr321.sol`, the `iszero(sdiv(c, E75))` gate
around `maximize`'s five steps forced true. Each inner step has its own gate
(`E38`, `E57`, `E66`, the `E74` loop and `E75`) that a coefficient of magnitude
at least `1e75` fails, so every step is a no-op for exactly the coefficients the
outer gate excludes. Only gas changes.

## Equivalent mutant: frozen `packLossy` copy, excess cap

`test/lib/LibParseDecimalFloatPr321.sol`, `excess > 67` relaxed to `> 68`. At an
excess of 68 the coefficient fits int224 (otherwise the `!fits` term reverts
first) and is nonzero (zero returned earlier), and `10 ** 68` fits int256;
`type(int224).max / 1e68` and `type(int224).min / 1e68` are both 0, so the
headroom check rejects every nonzero coefficient with the same
`ExponentOverflow(initialSignedCoefficient, initialExponent)`.

## Equivalent mutant: frozen `packLossy` copy, ceiling branch

`test/lib/LibParseDecimalFloatPr321.sol`, `initialExponent > 0` raised to
`> 10`. The branch is entered only when shedding pushed the exponent past
`int32.max`, and shedding raises it by at most ten (a coefficient has at most 77
digits and int224 keeps 67), so an initial exponent in `[1, 10]` ends in
`[1, 20]`, inside int32, and the branch never sees it.
