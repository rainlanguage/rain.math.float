# CLAUDE.md

Decimal floating-point math for Rainlang/DeFi. `Float` packs an int224
coefficient and an int32 exponent into one `bytes32`. Decimal, not binary, so
`0.1` is exact. The Rust/WASM layer reimplements none of it — every Rust
operation executes the Solidity through an in-memory revm, so the two cannot
disagree.

Everything else about this repo — layout, build commands, dependency list, what
CI runs — is discoverable from `foundry.toml`, `flake.nix` and
`.github/workflows/`. What follows is only what a capable agent would get WRONG.

## Hazards

**Rust tests read Foundry artifacts out of `out/`.** `cargo test` builds against
whatever `forge build` last wrote, so run `forge build` first or you are testing
stale bytecode instead of your change. `dependencies/` is fetched by
`forge soldeer install`; a compiler "file not found" on an import is that, not a
broken remapping.

**No NaN, no Infinity, no negative zero.** Nonsense reverts rather than
producing a special value. Do not introduce one — every consumer assumes any
`Float` it holds is a real number.

**Three packing modes, and which one a call site uses is a ruling, not a
preference.**

- `packLossless` reverts on any precision loss.
- `packLossy` surfaces a `lossless` flag and returns `FLOAT_ZERO` on exponent
  underflow. Parsing uses it because "this value rounds to zero" is a legitimate
  parse result, reported as `ParseDecimalPrecisionLoss`.
- `packArithmeticResult` tolerates coefficient truncation but reverts on
  exponent underflow. Every public arithmetic operation uses it: truncation
  preserves the order of magnitude, underflow does not.

**A deploy is part of a RELEASE. It never gates a merge.** Nothing in this repo
waits on a deploy to land, and no PR should carry a "redeploy before merge"
instruction. `src/lib/deploy/LibDecimalFloatDeploy.sol` carries the current
deploy constants alongside a frozen set per published soldeer tag, and documents
the convention that keeps version, tag and pins consistent; changing math or
format source moves the current bytecode, and therefore those constants, as a
release step.

**`src/generated/LogTables.pointers.sol` is generated but committed.**
Regenerate it with `script/BuildPointers.sol` whenever log table data changes.
Nothing regenerates it for you and nothing warns you that it is stale.
