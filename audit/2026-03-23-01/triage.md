# Audit Triage — 2026-03-23-01

Carried forward from 2026-03-10-01 triage.

| ID | Pass | Severity | Title | Status |
|----|------|----------|-------|--------|
| A10-9 | — | LOW | `parseDecimalFloat` wrapper inconsistently reverts for positive exponent overflow but returns soft error for negative | DOCUMENTED — asymmetry is correct: negative overflow rounds to zero (precision loss), positive has no approximation (revert). Added comments in source and test. |
| A11-3 | 4 | LOW | Inconsistent use of named constants vs magic numbers in `toBytes` overloads | FIXED |
| A11-4 | 2 | LOW | Log table tests have zero assertions -- they only call and log | FIXED — tests now assert toBytes output matches generated constants |
| A11-5 | 2 | LOW | No test verifies table data integrity against known log10 reference values | FIXED — toBytes output asserted against AOT-compiled constants; Rust cross-validation in PR #178 |
| A11-6 | 2 | LOW | No test for `toBytes` encoding correctness (round-trip or spot-check) | FIXED — each toBytes overload asserted equal to its generated constant |
