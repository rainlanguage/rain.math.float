# Audit Triage — 2026-03-10-01

Notes on IDs: When the same agent+number appears in multiple passes for
distinct findings, a `/pN` suffix disambiguates (e.g., A08-1/p1 vs A08-1/p3).
Deduplicated rows list the highest-severity instance and note absorbed
duplicates in the title.

| ID | Pass | Severity | Title | Status |
|----|------|----------|-------|--------|
| A08-7 | 5 | MEDIUM | Non-scientific `toDecimalString` panics on large positive exponents instead of reverting with `UnformatableExponent` (dupes: A08-1/p1 LOW, A08-3/p2 LOW) | FIXED |
| A01-1 | 0 | LOW | CLAUDE.md omits `script/` directory from architecture | FIXED |
| A01-2 | 0 | LOW | CLAUDE.md omits deployment workflow documentation | FIXED |
| A01-3 | 1 | LOW | `require` uses string revert message instead of custom error in `DecimalFloat.sol` (dupe: A01-01/p4 LOW) | FIXED |
| A01-4 | 2 | LOW | `log10(Float)` deployed-parity test entirely commented out | FIXED |
| A01-5 | 2 | LOW | `pow10(Float)` deployed-parity test entirely commented out | FIXED |
| A01-6 | 2 | LOW | `format(Float, bool)` overload has zero test coverage | FIXED |
| A01-7 | 2 | LOW | `format(Float)` default overload has zero test coverage | FIXED |
| A01-8 | 2 | LOW | `format(Float, Float, Float)` require revert path not tested | FIXED |
| A01-10 | 3 | LOW | `sub` NatSpec is semantically backwards -- says "a from b" but computes a - b (dupes: A06-9/p3 LOW, A06-22/p5 LOW, A01-07/p5 INFO) | FIXED |
| A01-11 | 3 | LOW | `div` parameter NatSpec is ambiguous in `DecimalFloat.sol` | FIXED |
| A01-12 | 3 | LOW | `pow10` NatSpec misleading -- says "raise to the power of 10" but computes 10^a (dupe: A01-05/p5 LOW) | FIXED |
| A02-4 | 2 | LOW | `CoefficientOverflow` error has no direct test (dupe: A06-1/p2 LOW) | FIXED |
| A03-1 | 2 | LOW | `UnformatableExponent` error has no test (dupe: A08-2/p2 LOW) | FIXED |
| A04-1 | 1 | LOW | `ParseDecimalFloatExcessCharacters` lacks a `position` parameter | WONTFIX — error is only used as a soft selector, never reverted; adding a param changes the selector and provides no benefit in the current architecture |
| A06-2 | 2 | LOW | `packLossy` lossy-but-packable path lacks targeted test | FIXED |
| A06-6 | 3 | LOW | `fromFixedDecimalLosslessPacked` NatSpec references non-existent `fromFixedDecimalLossyMem` (dupe: A06-23/p5 LOW) | FIXED |
| A06-7 | 3 | LOW | `packLossy` NatSpec missing `@return lossless` and references non-existent `PackedFloat` type | FIXED |
| A06-11 | 3 | LOW | NatSpec references non-existent function names `divide` and `power10` | FIXED |
| A06-12 | 3 | LOW | 22 of 34 functions missing `@return` NatSpec tags in `LibDecimalFloat.sol` | FIXED |
| A06-16 | 4 | LOW | `inv` uses unique `(lossless);` dead expression instead of `(Float result,)` destructuring | FIXED |
| A06-20 | 4 | LOW | `pow` function directly uses implementation internals, breaking packed API abstraction | FIXED |
| A07-01 | 4 | LOW | 7 unused imports in `LibDecimalFloatDeploy.sol` | FIXED |
| A08-1/p3 | 3 | LOW | `toDecimalString` missing `@param scientific` documentation | FIXED |
| A08-5/p4 | 4 | LOW | Redundant import path `../../lib/implementation/` in `LibFormatDecimalFloat.sol` | FIXED |
| A08-6 | 4 | LOW | `countSigFigs` is dead production code in `LibFormatDecimalFloat.sol` | FIXED |
| A09-1/p1 | 1 | LOW | `unabsUnsignedMulOrDivLossy` missing exponent overflow check on `exponent + 1` (dupes: A09-15/p2 LOW, A09-20/p5 INFO) | FIXED |
| A09-1/p3 | 3 | LOW | `div` missing all `@param` and `@return` NatSpec tags in implementation | FIXED |
| A09-5 | 3 | LOW | `inv` missing `@param` and `@return` NatSpec tags in implementation | FIXED |
| A09-9 | 3 | LOW | `compareRescale` missing `@param` and `@return` tags in implementation | FIXED |
| A09-11 | 2 | LOW | Six internal functions have no direct test coverage | FIXED |
| A09-12 | 2 | LOW | `minus` ExponentOverflow error path untested | FIXED |
| A09-13 | 2 | LOW | `log10` error paths (`Log10Zero`, `Log10Negative`) completely untested (dupes: A02-1/p2 LOW, A02-2/p2 LOW) | FIXED |
| A09-14 | 2 | LOW | `MulDivOverflow` error path in `mulDiv` untested (dupe: A02-3/p2 LOW) | FIXED |
| A09-16/p4 | 4 | LOW | Magic number `100` (alt small log table byte size) in `lookupAntilogTableY1Y2` | FIXED |
| A09-17/p4 | 4 | LOW | Magic number `2000` (antilog table byte size) in `lookupAntilogTableY1Y2` | FIXED |
| A09-22 | 5 | LOW | `div` scale selection binary search has gaps causing extra while-loop iterations | WONTFIX — gas optimization deferred to post-deploy |
| A10-1/p1 | 1 | LOW | Unchecked `exponent += eValue` can silently wrap on int256 overflow in `parseDecimalFloatInline` | FIXED |
| A10-1/p4 | 4 | LOW | Split imports from same module in `LibParseDecimalFloat.sol` | FIXED |
| A10-3 | 5 | LOW | Undocumented 67-digit limit and conflated overflow checks in parse rescaling | FIXED |
| A10-7 | 2 | LOW | No dedicated unit test for `ParseDecimalFloatExcessCharacters` from wrapper | FIXED |
| A10-8 | 2 | LOW | No dedicated unit test for `ParseDecimalPrecisionLoss` from `packLossy` in wrapper | FIXED |
| A10-9 | — | LOW | `parseDecimalFloat` wrapper inconsistently reverts for positive exponent overflow but returns soft error for negative | PENDING |
| A11-3 | 4 | LOW | Inconsistent use of named constants vs magic numbers in `toBytes` overloads | PENDING |
| A11-4 | 2 | LOW | Log table tests have zero assertions -- they only call and log | PENDING |
| A11-5 | 2 | LOW | No test verifies table data integrity against known log10 reference values | PENDING |
| A11-6 | 2 | LOW | No test for `toBytes` encoding correctness (round-trip or spot-check) | PENDING |
| A13-2/p3 | 3 | LOW | `Deploy.sol` constants are undocumented and inconsistently named | PENDING |
