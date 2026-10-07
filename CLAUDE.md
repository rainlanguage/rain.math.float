# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project Overview

Pure Solidity decimal floating-point math library for Rainlang/DeFi. The `Float`
type packs a 224-bit signed coefficient and 32-bit signed exponent into a single
`bytes32`. Decimal (not binary) representation ensures exact decimal values
(e.g., `0.1`). No NaN, Infinity, or negative zero — operations error on nonsense
rather than producing special values.

This repository is the library half of the rain.math.float split. It publishes
only the `rain-math-float` Soldeer package. The deployed concrete contract, the
on-chain deploy pins/snapshot, the deploy scripts/tests, and the Rust/WASM/npm
bindings live in `rain.math.float.deploy` and publish from there. The one Rust
crate here, `crates/tests`, is test-only and never published. It calls the
concretes in `test/concrete/` compiled from this source by their own ABI in
revm, fuzzed against exact references (`exact.rs`, `transcendental.rs`), and
cross-references the packed constants and log tables against values derived
independently.

## Architecture

### Source (`src/`)

- **`lib/LibDecimalFloat.sol`** — Public API: arithmetic, comparison,
  conversion, formatting, parsing. User-defined type `Float` wrapping `bytes32`.
- **`lib/implementation/`** — Internal arithmetic (512-bit intermediates for
  mul/div), normalization, packing.
- **`lib/parse/`** — String-to-Float parsing.
- **`lib/format/`** — Float-to-string formatting.
- **`lib/table/`** — Log lookup table source (`LibLogTable`); the transcendental
  functions take the deployed tables-contract address as a parameter.
- **`error/`** — Custom error definitions (CoefficientOverflow,
  ExponentOverflow, DivisionByZero, etc.).

### Tests (`test/`)

- **`src/lib/`** — The pure-math suite mirroring `src/lib/`.
- **`abstract/LogTest.sol`** — Test helper that rebuilds the combined log tables
  from `LibLogTable` source and deploys them as a data contract at a `create`
  address, so the transcendental tests (`log10`/`pow`/`pow10`/`sqrt`) run
  without any on-chain deploy pin.
- **`lib/`** — Reference (slow) implementations used to cross-check the library.

### Dependencies (`dependencies/`)

Managed by [Soldeer](https://soldeer.xyz) (`[dependencies]` in `foundry.toml`,
`libs = ['dependencies']`), not git submodules: forge-std,
`@openzeppelin-contracts`, rain-solmem, rain-string, rain-datacontract. Run
`forge soldeer install` to fetch them.

## Key Design Details

- 512-bit intermediate values in multiply/divide to preserve precision.
- Exponent overflow and underflow both revert from the public arithmetic surface
  (`ExponentOverflow` / `ExponentUnderflow`). Coefficient truncation is silently
  tolerated because it preserves the order of magnitude: digits are shed to fit
  the coefficient in int224 AND to lift an exponent below int32.min back to the
  floor. `ExponentUnderflow` is only the case where every digit has been shed.
  The pow10 and pow bounds add 1e-2147483648 absolute there.
- log10 and pow10 read no tables; both work in 1e50 fixed point. Their tables
  parameters are kept, unused.
- sqrt is correctly rounded, so monotone. log10, pow10 and pow are monotone
  within rounding error, not correctly rounded: order can flip by one ulp at a
  shared rounding tie, never more. Exact results stay exact. Bounds and
  contract: README; tests assert them via `test/lib/LibTestErrorBound.sol`.
- Three packing modes:
  - `packLossless`: reverts on any precision loss.
  - `packLossy`: surfaces the `lossless` flag, returns `FLOAT_ZERO` on exponent
    underflow. Used by parsing where underflow → "value rounds to zero" is a
    legitimate parse result reported via `ParseDecimalPrecisionLoss`.
  - `packArithmeticResult`: tolerates coefficient truncation, reverts on
    exponent underflow. Used by every public arithmetic operation but `minus`
    and `abs`.

## License

LicenseRef-DCL-1.0 (Rain Decentralized Computer License). All source files
require SPDX headers per REUSE.toml.
