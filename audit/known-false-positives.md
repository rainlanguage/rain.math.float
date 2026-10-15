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

## Equivalent mutant: pow oracle `k b` guard boundary

`crates/tests/src/differential.rs`, `check_pow_with`'s `|a| = 10^k` branch.
Changing `lead(&kb) >= 12` to `> 12` only changes the path at `lead(&kb) == 12`,
|k b| in [1e12, 1e13), where the original returns the `Truth::Past` band with
`over = rising`, `under = !rising`, `rising` the sign of k b, and the mutant
falls through. The two paths give every Solidity result the same verdict:

- k b whole: the mutant builds `e = 10^(k b)`, which fits an `isize` exponent,
  in a `Truth::Value` band that is `exact`, with
  `over = e > largest_float(negative)` and `under = e < smallest()`. For k b >=
  1e12, e is past the largest Float of either sign (under 10^2147483715) and not
  under the smallest, so `(over, under) = (true,
  false) = (rising, !rising)`;
  for k b <= -1e12, e is under the smallest Float (10^-2147483648) and not past
  the largest, so `(false, true) =
  (rising, !rising)`. A revert is therefore
  accepted or rejected exactly as under `Truth::Past`, with the same `input` for
  its data. A value result r is rejected by `Truth::Past` outright and by the
  exact band because `same(r, sign(e))` cannot hold: r decodes from a `bytes32`
  Float, so 0 < |r| < 10^2147483715 or r = 0, while |e| >= 10^1e12 or |e| <=
  10^-1e12.
- k b not whole: the mutant reaches the general band. `log10_of(10^k)` is
  exactly k (log10 of the coefficient 1 is 0), so z = k b exactly at 120 digits
  (at most 78 digits), |z| >= 1e12 > 2^33 = `huge()`, and the
  `magnitude(&z) > huge()` branch returns `range(rising, truth)` with the same
  `rising` (the sign of z = k b). Its `truth` is `Anywhere` only when
  `rel >= 1`: `rel = 5.00000012e-41 + N min(K1, K2 d)` with d =
  `distance_from_one(ax)` >= 9 for |k| >= 1, so `K2 d >= 1.35e-37 > K1` and the
  term is `N K1 <= 1e13 * 1.1728e-75 < 1e-61`, so `rel < 1` and `truth = Past`:
  the same band as the original.

The only distinguishing input is a `Dec` result whose exponent is past int32,
which no Float decodes to; the comparison is free at its boundary.
