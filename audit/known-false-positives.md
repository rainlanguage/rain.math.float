# Known false positives

Mutants that survive because the mutated program agrees with the original on
every input. Each entry carries the proof; a sampled or "no known input"
argument is not one.

## `.gas-snapshot`: fuzz statistics of a committed row

Mutant D3 of the scan recorded as `2026-10-14` in `mutation-test-scans.json`
(https://github.com/rainlanguage/rain.math.float/pull/711): in `.gas-snapshot`,
`LibDecimalFloatAbsTest:testAbsNegative(int256,int32) (runs: 5096, μ: 2577, ~: 2838)`
becomes `(runs: 5096, μ: 9999, ~: 2838)`.

Observer: `script/check-gas-snapshot.sh <committed> <fresh>`.

Proof: the check's verdict is a function of `normalise(committed)` and
`normalise(fresh)` alone, where `normalise` rewrites every line ending in
`(runs: N, μ: X, ~: Y)` to end in `(fuzz)`. The original and the mutated
committed file differ only in the `μ` field of one such line, so `normalise`
maps both to the same text, and for every fresh snapshot the two programs give
the same verdict. Fuzz rows comparing by name only is the check's specified
behaviour: fuzz gas is not reproducible across machines even with a fixed seed.
