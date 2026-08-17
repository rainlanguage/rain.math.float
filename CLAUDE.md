# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project Overview

Decimal floating-point math library for Rainlang/DeFi. The `Float` type packs a
224-bit signed coefficient and 32-bit signed exponent into a single `bytes32`.
Decimal (not binary) representation ensures exact decimal values (e.g., `0.1`).
No NaN, Infinity, or negative zero — operations error on nonsense rather than
producing special values.

Dual implementation: Solidity for on-chain, Rust/WASM for off-chain JS/TS
consumption. The Rust crate uses revm to execute Solidity via an in-memory EVM,
ensuring identical behavior.

## Build Commands

### Solidity (Foundry)

```bash
forge build          # Compile contracts
forge test           # Run all Solidity tests (5096 fuzz runs)
forge test --mt testFunctionName  # Run specific test by name
forge test -vvvv     # Verbose trace output for debugging
```

### Rust

```bash
cargo build                                          # Build native
cargo build --target wasm32-unknown-unknown --lib -r  # Build WASM
cargo test                                           # Run Rust tests
cargo test test_name                                 # Run specific test
```

Rust tests depend on Foundry build artifacts (`out/`). Run `forge build` before
`cargo test` if artifacts are missing.

### JavaScript/WASM

```bash
npm install
npm run build   # Full pipeline: Rust WASM → wasm-bindgen → base64 embed → CJS/ESM dist
npm test        # TypeScript type check + vitest (tests in test_js/)
```

### Nix

```bash
nix develop     # Enter dev shell with all tooling
```

### Deployment

Contracts are deployed deterministically via the Zoltu proxy to the same address
on all supported networks (Arbitrum, Base, Base Sepolia, Flare, Polygon). The
deterministic address is a function of bytecode + salt only — not the branch or
deployer — so a successful deploy from any branch lands at the same address a
main-branch deploy would.

**Deploys never gate merges.** Publishing a release and broadcasting a
deployment are separate, decoupled steps. `package-release.yaml` publishes the
cargo/npm/soldeer artifacts; the on-chain deploy is a manual `workflow_dispatch`
of `manual-sol-artifacts.yaml` that a human triggers whenever it suits. No PR
waits on a broadcast, and no PR should carry a "redeploy before merge"
instruction.

That works because the pinned constants are _derived_, not observed. A Zoltu
address is a function of bytecode + salt, so a source change's new address and
codehash are computed from the build and committed in the same PR that changes
the source — `testDeployAddress`, `testExpectedCodeHashDecimalFloat` and their
log-tables siblings run entirely in-memory and never touch a network.

**Deploying** (a human's manual dispatch, never a step in a PR):

`gh workflow run manual-sol-artifacts.yaml --ref <branch> -f suite=decimal-float`
(use `log-tables` only when table bytecode changes, which is rare). The workflow
runs `script/Deploy.sol` with `--broadcast --verify` across all networks, using
`PRIVATE_KEY` regardless of ref. There are two suites, and log tables must be
deployed before DecimalFloat when the tables are being redeployed:

```bash
DEPLOYMENT_KEY=<key> DEPLOYMENT_SUITE=log-tables forge script script/Deploy.sol:Deploy --broadcast --verify
DEPLOYMENT_KEY=<key> DEPLOYMENT_SUITE=decimal-float forge script script/Deploy.sol:Deploy --broadcast --verify
```

**Pinned constants** live in `src/lib/deploy/LibDecimalFloatDeploy.sol` in two
tiers:

- The unsuffixed constants are the current head's derived address and codehash.
  Any source change to `LibDecimalFloat` or `LibFormatDecimalFloat` invalidates
  them, and `testDeployAddress` / `testExpectedCodeHashDecimalFloat` fail until
  they are regenerated and committed.
- The `*_<major>_<minor>_<patch>` constants are frozen per-release records: the
  address and codehash derived from that published soldeer tag's own bytecode,
  written once and never updated afterwards.
  `script/check-published-deploy-constants.sh` queries the registry and
  `testAllPublishedSoldeerTagsHaveAFullConstantSuite` fails when a published tag
  has no suite, so publishing a tag obliges pinning its record. Pinning is a
  derivation from the tag's source, so it never waits on a broadcast either.

Fork RPC URLs for `testProdDeployment*` come from `foundry.toml`'s
`[rpc_endpoints]` (`ARBITRUM_RPC_URL`, `BASE_RPC_URL`, `BASE_SEPOLIA_RPC_URL`,
`FLARE_RPC_URL`, `POLYGON_RPC_URL`); the `CI_DEPLOY_*_ETHERSCAN_API_KEY` vars
are `[etherscan]` verification keys only. `testProdDeployment*` asserts that the
_current_ unsuffixed pins are already live on chain, which is the one place
premerge CI still waits on a broadcast — the residual pre-split shape, tracked
by the deploy-record migration in #252.

## Architecture

### Solidity Layer (`src/`)

- **`lib/LibDecimalFloat.sol`** — Public API: arithmetic, comparison,
  conversion, formatting, parsing. User-defined type `Float` wrapping `bytes32`.
- **`lib/implementation/`** — Internal arithmetic (512-bit intermediates for
  mul/div), normalization, packing.
- **`lib/parse/`** — String-to-Float parsing.
- **`lib/format/`** — Float-to-string formatting.
- **`lib/table/`** — Log lookup tables (deployed as a data contract at a
  deterministic address).
- **`concrete/DecimalFloat.sol`** — Exposes library functions as contract
  methods (required for Rust/revm interop via ABI).
- **`error/`** — Custom error definitions (CoefficientOverflow,
  ExponentOverflow, DivisionByZero, etc.).

### Scripts (`script/`)

- **`Deploy.sol`** — Production deployment script using Zoltu deterministic
  proxy. Deploys log tables and DecimalFloat contract to all supported networks.
- **`Build.sol`** — Generates `src/generated/LogTables.pointers.sol` (committed
  to repo; must be regenerated if log table data changes).

### Rust Layer (`crates/float/`)

- **`lib.rs`** — `Float` struct wrapping `B256`, implements
  `Add`/`Sub`/`Mul`/`Div`/`Neg`. Uses `alloy::sol!` macro to generate bindings
  from Foundry JSON artifacts in `out/`.
- **`js_api.rs`** — `#[wasm_bindgen]` exports for JS consumption (parse, format,
  arithmetic, conversions).
- **`evm.rs`** — In-memory EVM setup via revm. All Rust float operations
  delegate to Solidity through this.
- **`error.rs`** — Maps Solidity error selectors to Rust error types.

### JavaScript Layer

- **`scripts/build.js`** — Build pipeline: compiles WASM, runs wasm-bindgen,
  base64-encodes WASM into JS modules for both CJS and ESM.
- **`test_js/`** — Vitest tests for the WASM bindings.
- **`dist/`** — Generated output (CJS + ESM with embedded WASM).

### Dependencies (`dependencies/`)

Managed by [Soldeer](https://soldeer.xyz) (`[dependencies]` in `foundry.toml`,
`libs = ['dependencies']`), not git submodules: forge-std,
`@openzeppelin-contracts`, rain-solmem, rain-string, rain-datacontract,
rain-deploy, rain-sol-codegen. Run `forge soldeer install` to fetch them.

## Key Design Details

- 512-bit intermediate values in multiply/divide to preserve precision.
- Exponent overflow and underflow both revert from the public arithmetic surface
  (`ExponentOverflow` / `ExponentUnderflow`). Coefficient truncation on values
  too large for int224 is silently tolerated because it preserves the order of
  magnitude.
- Log/power use lookup table approximations with linear interpolation (table
  deployed as a data contract).
- Three packing modes:
  - `packLossless`: reverts on any precision loss.
  - `packLossy`: surfaces the `lossless` flag, returns `FLOAT_ZERO` on exponent
    underflow. Used by parsing where underflow → "value rounds to zero" is a
    legitimate parse result reported via `ParseDecimalPrecisionLoss`.
  - `packArithmeticResult`: tolerates coefficient truncation, reverts on
    exponent underflow. Used by every public arithmetic operation.
- Solidity compiler: 0.8.25, EVM target: Cancun, optimizer: 1,000,000 runs.

## License

LicenseRef-DCL-1.0 (Rain Decentralized Computer License). All source files
require SPDX headers per REUSE.toml.
