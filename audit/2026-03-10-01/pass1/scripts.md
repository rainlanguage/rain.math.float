# Audit Pass 1 (Security): Scripts

**Date:** 2026-03-10
**Agents:** A12, A13
**Files reviewed:**
- `script/BuildPointers.sol` (A12)
- `script/Deploy.sol` (A13)

---

## A12: `script/BuildPointers.sol`

### Evidence of Thorough Reading

**Contract:** `BuildPointers` (line 10), inherits `Script` (forge-std)

**Imports (lines 5-8):**
- `Script` from `forge-std/Script.sol`
- `LibCodeGen` from `rain.sol.codegen/src/lib/LibCodeGen.sol`
- `LibFs` from `rain.sol.codegen/src/lib/LibFs.sol`
- `LibLogTable` from `../src/lib/table/LibLogTable.sol`

**Functions:**
- `run()` external (line 11) -- the sole entry point

**Types/Errors/Constants defined:** None

**Functional summary:**
The script calls `LibFs.buildFileForContract` to generate `src/generated/LogTables.pointers.sol`. It passes `address(0)` as the contract instance (used only for a bytecode hash constant in the generated header). The body is built by concatenating five `LibCodeGen.bytesConstantString` calls, each encoding one of the five log/antilog tables:
1. `LOG_TABLES` from `LibLogTable.logTableDec()` (line 18)
2. `LOG_TABLES_SMALL` from `LibLogTable.logTableDecSmall()` (line 24)
3. `LOG_TABLES_SMALL_ALT` from `LibLogTable.logTableDecSmallAlt()` (line 29)
4. `ANTI_LOG_TABLES` from `LibLogTable.antiLogTableDec()` (line 37)
5. `ANTI_LOG_TABLES_SMALL` from `LibLogTable.antiLogTableDecSmall()` (line 42)

`LibFs.buildFileForContract` (reviewed in `rain.sol.codegen/src/lib/LibFs.sol`) writes to the path `src/generated/LogTables.pointers.sol`, deleting any pre-existing file at that path first.

### Security Review

**File system operations:**
- The output path is hardcoded via `LibFs.pathForContract("LogTables")` which resolves to `src/generated/LogTables.pointers.sol`. The path is deterministic and within the source tree. No user-supplied input influences the path.
- `LibFs.buildFileForContract` unconditionally deletes the existing file before writing. This is by-design idempotency, documented in `LibFs.sol` line 26.

**Data integrity:**
- The table data is generated purely from `LibLogTable` pure functions. No external input, no environment variables, no RPC calls. The output is deterministic for a given version of the source code.
- The generated file is committed to the repository, so any drift between the generator and the committed output would be visible in version control.

### Findings

No security findings. The script is a deterministic code generator with no external inputs, no private key handling, no network interaction, and a hardcoded output path within the source tree.

---

## A13: `script/Deploy.sol`

### Evidence of Thorough Reading

**Constants (lines 11-12):**
- `DEPLOYMENT_SUITE_TABLES` = `keccak256("log-tables")` (line 11)
- `DEPLOYMENT_SUITE_CONTRACT` = `keccak256("decimal-float")` (line 12)

**Contract:** `Deploy` (line 14), inherits `Script` (forge-std)

**Imports (lines 5-9):**
- `Script` from `forge-std/Script.sol`
- `LibDataContract` from `rain.datacontract/lib/LibDataContract.sol`
- `LibDecimalFloatDeploy` from `../src/lib/deploy/LibDecimalFloatDeploy.sol`
- `LibRainDeploy` from `rain.deploy/lib/LibRainDeploy.sol`
- `DecimalFloat` from `../src/concrete/DecimalFloat.sol`

**State variables:**
- `sDepCodeHashes` (line 15): `mapping(string => mapping(address => bytes32))` internal -- stores dependency code hashes per network for cross-phase verification

**Functions:**
- `run()` external (line 17) -- the sole entry point

**Types/Errors defined:** None (errors are in `LibRainDeploy`)

**Functional summary:**
1. Reads `DEPLOYMENT_KEY` from environment as `uint256` (line 18).
2. Reads `DEPLOYMENT_SUITE` from environment with default `"decimal-float"` (line 20).
3. Hashes the suite string and dispatches:
   - **`log-tables` suite** (lines 21-32): Deploys combined log tables as a data contract. Dependencies: none (`new address[](0)`). Expected address and code hash from `LibDecimalFloatDeploy`.
   - **`decimal-float` suite** (lines 33-46): Deploys `DecimalFloat` contract. Dependency: the log tables address (`ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS`). Expected address and code hash from `LibDecimalFloatDeploy`.
   - **else** (lines 47-51): Reverts with an error message.

`LibRainDeploy.deployAndBroadcast` (reviewed in `rain.deploy/lib/LibRainDeploy.sol`) handles:
- Deriving the deployer address from the private key via `vm.rememberKey` (line 257 of LibRainDeploy)
- Dependency checking on all networks (code existence + codehash recording)
- Deployment via Zoltu factory on each network with idempotent skip
- Post-deployment verification (address match + codehash match)

### Security Review

**Private key handling:**
- The private key is read from the `DEPLOYMENT_KEY` environment variable (line 18) via `vm.envUint`. This is the standard Foundry pattern.
- The key is passed to `LibRainDeploy.deployAndBroadcast` which calls `vm.rememberKey(deployerPrivateKey)`. This derives and caches the address. The key itself is only used for `vm.startBroadcast(deployer)` which signs transactions.
- The private key is never logged. The deployer *address* is logged by `LibRainDeploy` (line 259) but not the key itself.

**Deployment verification:**
- `LibRainDeploy.deployAndBroadcast` performs two-phase verification:
  1. **Pre-deploy:** `checkDependencies` forks each network and verifies Zoltu factory codehash + all dependency addresses have code. Records dependency codehashes.
  2. **Deploy phase:** `deployToNetworks` re-verifies Zoltu factory and dependency codehashes before each per-network deployment. Post-deploy, it checks `deployedAddress == expectedAddress` and `deployedAddress.codehash == expectedCodeHash`.
- Idempotent: if code already exists at `expectedAddress`, deployment is skipped.

**Dependency checks:**
- For `log-tables` suite: no dependencies (empty array). The Zoltu factory itself is still verified.
- For `decimal-float` suite: the log tables address is listed as a dependency and verified to have code on each target network before deployment proceeds.

**Access control:**
- The script is a Foundry `Script` -- it can only be executed by someone running `forge script` with the appropriate environment variables. No on-chain access control is needed or relevant.

**Input validation:**
- The `DEPLOYMENT_SUITE` environment variable is validated via the `else` revert (lines 47-51). Unknown suite values cause a revert with a descriptive message.
- The `DEPLOYMENT_KEY` read via `vm.envUint` will revert if the variable is not set.

### Findings

#### A13-1: Default deployment suite may mask operator intent (INFO)

**File:** `script/Deploy.sol`
**Line:** 20

The `DEPLOYMENT_SUITE` environment variable defaults to `"decimal-float"` when unset (via `vm.envOr`). If an operator forgets to set the variable, the script will silently proceed to deploy the `DecimalFloat` contract rather than erroring out. Given that deployment ordering matters (tables must be deployed before the contract), a missing variable could cause a failed deployment (caught by dependency checks) or an unintended successful deployment if tables are already present.

This is INFO-level because:
- `LibRainDeploy.checkDependencies` would catch any missing table dependencies before the deploy phase.
- An experienced operator would know to set the variable.
- The default to `"decimal-float"` is the more common operation.

#### A13-2: No explicit ordering enforcement between deployment suites (INFO)

**File:** `script/Deploy.sol`
**Lines:** 21-46

The `log-tables` suite must be deployed before the `decimal-float` suite because `DecimalFloat` depends on the log tables contract. While the dependency check in `LibRainDeploy.checkDependencies` would fail if tables are not deployed, the error message comes from `LibRainDeploy` (`MissingDependency`) rather than from `Deploy.sol` itself. The ordering constraint is implicit and undocumented in the script.

This is INFO-level because:
- The dependency system does catch the ordering violation at runtime.
- The constraint is documented in the existing fix A01-2.

---

## Summary

| ID | Severity | File | Description |
|----|----------|------|-------------|
| A13-1 | INFO | `script/Deploy.sol:20` | Default deployment suite may mask operator intent |
| A13-2 | INFO | `script/Deploy.sol:21-46` | No explicit ordering enforcement between deployment suites |

No LOW or higher findings. Both scripts are well-structured. `BuildPointers.sol` is a pure code generator with no security surface. `Deploy.sol` delegates all security-critical operations (key handling, address verification, codehash verification, dependency checking) to `LibRainDeploy`, which implements thorough two-phase verification.
