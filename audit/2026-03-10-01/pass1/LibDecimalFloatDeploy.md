# Audit Pass 1 (Security) -- LibDecimalFloatDeploy.sol

**Agent:** A07
**File:** `src/lib/deploy/LibDecimalFloatDeploy.sol`
**Date:** 2026-03-10

---

## Evidence of Thorough Reading

### Library Name
- `LibDecimalFloatDeploy` (line 19)

### Functions
| Function | Line | Visibility | Mutability |
|---|---|---|---|
| `combinedTables()` | 42 | `internal` | `pure` |

### Constants
| Name | Line | Type | Value |
|---|---|---|---|
| `ZOLTU_DEPLOYED_LOG_TABLES_ADDRESS` | 23 | `address` | `0xc51a14251b0dcF0ae24A96b7153991378938f5F5` |
| `LOG_TABLES_DATA_CONTRACT_HASH` | 27 | `bytes32` | `0x2573004ac3a9ee7fc8d73654d76386f1b6b99e34cdf86a689c4691e47143420f` |
| `ZOLTU_DEPLOYED_DECIMAL_FLOAT_ADDRESS` | 32 | `address` | `0x12A66eFbE556e38308A17e34cC86f21DcA1CDB73` |
| `DECIMAL_FLOAT_CONTRACT_HASH` | 36 | `bytes32` | `0x705cdef2ed9538557152f86cd0988c748e0bd647a49df00b3e4f100c3544a583` |

### Types / Errors Defined
None defined in this file. `WriteError` is imported but unused.

### Imports
| Import | Source | Used in File Body? |
|---|---|---|
| `LOG_TABLES` | `LogTables.pointers.sol` | Yes (line 44) |
| `LOG_TABLES_SMALL` | `LogTables.pointers.sol` | Yes (line 45) |
| `LOG_TABLES_SMALL_ALT` | `LogTables.pointers.sol` | Yes (line 46) |
| `ANTI_LOG_TABLES` | `LogTables.pointers.sol` | Yes (line 47) |
| `ANTI_LOG_TABLES_SMALL` | `LogTables.pointers.sol` | Yes (line 48) |
| `LibDataContract`, `DataContractMemoryContainer` | `rain.datacontract` | No |
| `LibBytes` | `rain.solmem` | No |
| `LibMemCpy`, `Pointer` | `rain.solmem` | No |
| `DecimalFloat` | `concrete/DecimalFloat.sol` | No (re-exported for consumers) |
| `LOG_TABLE_DISAMBIGUATOR` | `LibLogTable.sol` | Yes (line 49) |
| `WriteError` | `ErrDecimalFloat.sol` | No |

---

## Security Analysis

### Hardcoded Addresses and Code Hashes

The file defines two hardcoded addresses and their expected codehashes for deterministic deployment via the Zoltu proxy. These constants are consumed by:

1. **`script/Deploy.sol`** -- The deployment script passes these constants to `LibRainDeploy.deployAndBroadcast`, which verifies the deployed codehash matches before proceeding.
2. **`test/src/lib/deploy/LibDecimalFloatDeploy.t.sol`** -- Tests verify that deploying via Zoltu produces the expected address and codehash.
3. **`test/src/lib/deploy/LibDecimalFloatDeployProd.t.sol`** -- Production fork tests verify that all supported networks (Arbitrum, Base, Base Sepolia, Flare, Polygon) have the contracts deployed at the expected addresses with correct codehashes.
4. **`test/abstract/LogTest.sol`** -- Test helper deploys combined tables and verifies codehash.

The addresses are deterministic (derived from Zoltu's deployment proxy with known creation code), so they are correctly constant across EVM-compatible chains. The codehash provides a second layer of verification that the deployed bytecode is exactly as expected.

The runtime library (`LibDecimalFloat.sol`) does NOT hardcode the tables address. Instead, `log10`, `pow10`, and `pow` accept `tablesDataContract` as an explicit parameter, so there is no risk of silently using the wrong tables at runtime -- the caller is responsible for providing the correct address.

### Data Integrity of Combined Tables

The `combinedTables()` function uses `abi.encodePacked` to concatenate five table byte constants and the `LOG_TABLE_DISAMBIGUATOR`. The use of `abi.encodePacked` on fixed-size `bytes` constants is safe here because there is no dynamic-length ambiguity -- each constant is a fixed hex literal. The disambiguator (`keccak256("LOG_TABLE_DISAMBIGUATOR_1")`) ensures the creation code is unique even if table contents happen to collide with other data contract deployments.

### Deployment to Wrong Address

The deployment flow in `Deploy.sol` passes both the expected address and expected codehash to `LibRainDeploy.deployAndBroadcast`. The Zoltu deterministic deployment proxy guarantees address determinism. If the creation code changes (e.g., table data modified), the address and codehash would both change, and the deployment script would catch the mismatch. This is well-guarded.

---

## Findings

### A07-1 [INFO] Unused Imports

**Lines:** 12-15, 17

Several imports are present in the file but never used in its body:
- `LibDataContract`, `DataContractMemoryContainer` (line 12)
- `LibBytes` (line 13)
- `LibMemCpy`, `Pointer` (line 14)
- `WriteError` (line 17)

`DecimalFloat` (line 15) is imported but only used in NatSpec comments; however, it serves the purpose of being re-exported to downstream consumers (e.g., `test/src/lib/deploy/LibDecimalFloatDeploy.t.sol` imports both `LibDecimalFloatDeploy` and `DecimalFloat` from this file's path).

**Severity:** Informational. Unused imports have no security impact but increase compile-time noise and may confuse auditors/reviewers. The Solidity compiler warns about these.

**Recommendation:** Remove `LibDataContract`, `DataContractMemoryContainer`, `LibBytes`, `LibMemCpy`, `Pointer`, and `WriteError` imports. Keep `DecimalFloat` only if it is intentionally re-exported.

---

## Summary

No security findings at LOW or above. The file is a well-structured deployment configuration library. The hardcoded addresses and codehashes are properly verified through both deterministic deployment mechanics and test coverage across multiple networks. The runtime library does not rely on these constants, requiring callers to explicitly provide the tables address.
