---
paths:
  - "src/**/*.sol"
  - "test/**/*.sol"
  - "script/**/*.sol"
---

# Solidity

Multiply and divide carry 512-bit intermediates to preserve precision. Log and
power use lookup-table approximations with linear interpolation; the table
ships as a data contract at a deterministic address.

Three packing modes, chosen by what the caller can tolerate:

- `packLossless` reverts on any precision loss.
- `packLossy` surfaces the `lossless` flag and returns `FLOAT_ZERO` on exponent
  underflow. Parsing uses it, because "this value rounds to zero" is a
  legitimate parse result there, reported via `ParseDecimalPrecisionLoss`.
- `packArithmeticResult` tolerates coefficient truncation but reverts on
  exponent underflow. Every public arithmetic operation uses it.

Compiler 0.8.25, EVM target Cancun, optimizer 1,000,000 runs.
