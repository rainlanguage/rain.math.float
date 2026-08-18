# CLAUDE.md

Decimal floating-point math for Rainlang/DeFi. `Float` packs a 224-bit signed
coefficient and a 32-bit signed exponent into one `bytes32`. Decimal, not
binary, so values like `0.1` are exact. There is no NaN, Infinity or negative
zero — operations revert on nonsense rather than producing a special value.

## Rust is not a second implementation

`crates/float` runs the Solidity in an in-memory EVM (revm), so every Rust and
WASM operation IS the Solidity one. Fix math in Solidity; never reimplement it
in Rust. Bindings are generated from Foundry's `out/`, so `cargo test` needs a
`forge build` first.

## Deploys never gate merges

A source-changing PR regenerates its deployment record and lands on that record
alone. The on-chain deploy is a separate manual dispatch
(`manual-sol-artifacts.yaml`), run when someone decides to publish, and log
tables must land before `DecimalFloat` — its constructor checks their codehash.
Both are placed by the Zoltu proxy, whose address is a pure function of the
creation code, so a deploy from any branch lands where a main deploy would.

`test/src/lib/deploy/LibDecimalFloatDeployProd.t.sol` forks the five supported
networks and asserts the current record's addresses already carry the expected
code, so it goes red between a bytecode change and the deploy that publishes it.
That is a statement about the state of the chains, not about the branch.

Addresses and code hashes are generated, never hand-written. `script/Build.sol`
writes the current record to `src/generated/` and freezes it per release under
`src/generated/<tag>/` (tag = `[package].version`, dots as underscores);
`LibDecimalFloatDeploy` only aliases the current one. Any change to
`LibDecimalFloat` or `LibFormatDecimalFloat` changes the deployed bytecode, so
re-run the script and commit its output — `LibDecimalFloatDeployTaggedConstants`
re-derives every frozen record offline and fails when the two drift.

## Semantics to know before changing arithmetic

- Multiply and divide carry 512-bit intermediates to preserve precision.
- Exponent overflow and underflow both revert from the public surface
  (`ExponentOverflow` / `ExponentUnderflow`). Coefficient truncation on values
  too large for `int224` is silently tolerated: it preserves the magnitude.
- Three packing modes, and choosing the wrong one is a behaviour change.
  `packLossless` reverts on any precision loss. `packLossy` surfaces a
  `lossless` flag and returns `FLOAT_ZERO` on exponent underflow — parsing wants
  this, where underflow is a legitimate result reported as
  `ParseDecimalPrecisionLoss`. `packArithmeticResult` tolerates coefficient
  truncation and reverts on exponent underflow; every public arithmetic
  operation uses it.
- Log and power are lookup-table approximations with linear interpolation, the
  tables held on-chain as a data contract.

Every source file needs an SPDX header — `REUSE.toml` enforces it.
