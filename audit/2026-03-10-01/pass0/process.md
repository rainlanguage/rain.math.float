# Audit Pass 0: Process Review

**Date:** 2026-03-10
**Files reviewed:** CLAUDE.md, README.md, REUSE.toml, foundry.toml

## Evidence of Reading

### CLAUDE.md
- Sections: Project Overview, Build Commands (Solidity, Rust, JavaScript/WASM, Nix), Architecture (Solidity Layer, Rust Layer, JavaScript Layer, Dependencies), Key Design Details, License
- Build commands: forge build/test, cargo build/test, npm install/build/test, nix develop
- Architecture references: LibDecimalFloat.sol, implementation/, parse/, format/, table/, DecimalFloat.sol, error/, lib.rs, js_api.rs, evm.rs, error.rs, build.js, test_js/, dist/
- Dependencies listed: forge-std, rain.string, rain.datacontract, rain.math.fixedpoint, rain.deploy, rain.sol.codegen

### README.md
- Sections: Context, Rounding vs. erroring vs. approximating (Rounding direction, Approach to preserving precision, Exponent underflow, Packing, Fixed decimal conversions, Exponent overflow, Other overflows, Uncalculable values, Unimplemented math, Parsing/formatting issues, Lossy conversions, Approximations)
- External reference: rainlanguage/rain.math.float#88

### REUSE.toml
- Single annotations block covering config/metadata files
- SPDX: LicenseRef-DCL-1.0

### foundry.toml
- Settings: solc 0.8.25, optimizer 1000000 runs, evm cancun, fuzz 5096 runs
- RPC endpoints: arbitrum, base, base_sepolia, flare, polygon
- Etherscan keys for same 5 networks

## Findings

### A01-1: CLAUDE.md omits `script/` directory from architecture (LOW)

The Architecture section documents `src/`, `crates/float/`, `scripts/`, `test_js/`, and `dist/` but does not mention `script/` which contains `Deploy.sol` and `BuildPointers.sol`. These are operationally critical — Deploy.sol is the production deployment script, and BuildPointers.sol generates committed source code (`src/generated/LogTables.pointers.sol`). A future session could be unaware of how deployment or pointer regeneration works.

### A01-2: CLAUDE.md omits deployment workflow documentation (LOW)

There is no mention of how to deploy contracts, what networks are supported, what environment variables are needed (`DEPLOYMENT_KEY`, `DEPLOYMENT_SUITE`, `CI_DEPLOY_*_RPC_URL`), or where deterministic addresses are defined (`LibDecimalFloatDeploy.sol`). A future session asked to deploy would need to reverse-engineer the workflow from `script/Deploy.sol` and the CI config.

### A01-3: CLAUDE.md omits test directory structure (INFO)

The architecture section doesn't describe the `test/` directory or its organization. Test files mirror the source tree under `test/src/` but this convention is undocumented.
