# Audit Pass 1: Security — `src/lib/format/LibFormatDecimalFloat.sol` (A08)

## Evidence of Thorough Reading

**Library:** `LibFormatDecimalFloat`

**Imports (lines 5-8):**
- `LibDecimalFloat`, `Float` from `../LibDecimalFloat.sol`
- `LibDecimalFloatImplementation` from `../../lib/implementation/LibDecimalFloatImplementation.sol`
- `Strings` from `openzeppelin-contracts/contracts/utils/Strings.sol`
- `UnformatableExponent` from `../../error/ErrFormat.sol`

**Functions:**
| Function | Line | Visibility |
|----------|------|------------|
| `countSigFigs(int256, int256)` | 18 | `internal pure` |
| `toDecimalString(Float, bool)` | 58 | `internal pure` |

No assembly blocks, no constants defined, no custom errors defined (one imported).

## Findings

### A08-1 [LOW]: Unguarded overflow in non-scientific mode for large positive exponents (line 80)

`signedCoefficient *= int256(10) ** uint256(exponent)` can overflow int256 for valid packed Float values (e.g., coefficient near int224.max with exponent >= 10), producing an unhandled `Panic(0x11)` instead of the descriptive `UnformatableExponent` error used for the analogous negative-exponent case on line 85. The negative path guards with `exponent < -76`, but the positive path has no guard at all.

**Impact:** Callers formatting valid Float values with large positive exponents get an opaque panic instead of a meaningful error.
