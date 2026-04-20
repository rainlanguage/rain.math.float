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

**Typical flow for a source-changing PR**: trigger the `Manual sol artifacts`
GitHub workflow on the PR's branch before merge.
`gh workflow run manual-sol-artifacts.yaml --ref <branch> -f suite=decimal-float`
(use `log-tables` only when table bytecode changes, which is rare). The workflow
runs `script/Deploy.sol` with `--broadcast --verify` across all networks, using
`PRIVATE_KEY` regardless of ref. Do NOT wait for merge before deploying — there
is nothing to gain from waiting, and the CI deploy-constant tests need updating
anyway based on the deployed address.

**Two deployment suites** (log-tables must be deployed first if redeploying
tables):

```bash
DEPLOYMENT_KEY=<key> DEPLOYMENT_SUITE=log-tables forge script script/Deploy.sol:Deploy --broadcast --verify
DEPLOYMENT_KEY=<key> DEPLOYMENT_SUITE=decimal-float forge script script/Deploy.sol:Deploy --broadcast --verify
```

Expected addresses and code hashes are in
`src/lib/deploy/LibDecimalFloatDeploy.sol`. Any source change to
`LibDecimalFloat` or `LibFormatDecimalFloat` invalidates these constants; CI's
`testDeployAddress` and `testExpectedCodeHashDecimalFloat` will fail until
they're regenerated and committed. Network RPC URLs are configured in
`foundry.toml` via `CI_DEPLOY_*_RPC_URL` env vars.

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
- **`BuildPointers.sol`** — Generates `src/generated/LogTables.pointers.sol`
  (committed to repo; must be regenerated if log table data changes).

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

### Dependencies (`lib/`)

Git submodules: forge-std, rain.string, rain.datacontract, rain.math.fixedpoint,
rain.deploy, rain.sol.codegen.

## Key Design Details

- 512-bit intermediate values in multiply/divide to preserve precision.
- Exponent underflow silently rounds toward zero; exponent overflow reverts.
- Log/power use lookup table approximations with linear interpolation (table
  deployed as a data contract).
- Two packing modes: lossless (reverts on precision loss) and lossy (returns
  bool flag).
- Solidity compiler: 0.8.25, EVM target: Cancun, optimizer: 1,000,000 runs.

## License

LicenseRef-DCL-1.0 (Rain Decentralized Computer License). All source files
require SPDX headers per REUSE.toml.
