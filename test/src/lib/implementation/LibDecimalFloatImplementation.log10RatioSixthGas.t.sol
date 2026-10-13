// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    POW_FIXED_ONE,
    POW_FIXED_SQRT_ONE,
    POW_FIXED_ONE_ODD,
    POW_FIXED_ONE_ODD_INVERSE,
    POW_FIXED_ONE_TWOS_MASK
} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Test, console2} from "forge-std-1.17.0/src/Test.sol";

/// Logs the gas of `log10Ratio`'s z^6 step, floor(t x / 1e50) for x its
/// zSquared and t = floor(x^2 / 1e50), inside the call so ABI overhead is
/// excluded: the in-place 512-bit `mulDivFixed` it replaced, the split of x by
/// 2^50 it uses, and a split of x by 1e25, each split in assembly and in plain
/// Solidity. Run with `-vv`.
contract LibDecimalFloatImplementationLog10RatioSixthGasTest is Test {
    function wideAssembly(uint256 t, uint256 x) external view returns (uint256 r, uint256 g) {
        uint256 inverse = POW_FIXED_ONE_ODD_INVERSE;
        g = gasleft();
        assembly ("memory-safe") {
            let mm := mulmod(t, x, not(0))
            let prod0 := mul(t, x)
            let remainder := mulmod(t, x, POW_FIXED_ONE)
            r := mul(or(shr(50, sub(prod0, remainder)), shl(206, sub(sub(mm, prod0), gt(remainder, prod0)))), inverse)
        }
        g -= gasleft();
    }

    function splitAssembly(uint256 t, uint256 x) external view returns (uint256 r, uint256 g) {
        g = gasleft();
        assembly ("memory-safe") {
            r := div(
                add(mul(t, div(x, POW_FIXED_SQRT_ONE)), div(mul(t, mod(x, POW_FIXED_SQRT_ONE)), POW_FIXED_SQRT_ONE)),
                POW_FIXED_SQRT_ONE
            )
        }
        g -= gasleft();
    }

    function splitSolidity(uint256 t, uint256 x) external view returns (uint256 r, uint256 g) {
        g = gasleft();
        unchecked {
            r = (t * (x / POW_FIXED_SQRT_ONE) + t * (x % POW_FIXED_SQRT_ONE) / POW_FIXED_SQRT_ONE) / POW_FIXED_SQRT_ONE;
        }
        g -= gasleft();
    }

    function shiftAssembly(uint256 t, uint256 x) external view returns (uint256 r, uint256 g) {
        g = gasleft();
        assembly ("memory-safe") {
            r := div(add(mul(t, shr(50, x)), shr(50, mul(t, and(x, POW_FIXED_ONE_TWOS_MASK)))), POW_FIXED_ONE_ODD)
        }
        g -= gasleft();
    }

    function shiftSolidity(uint256 t, uint256 x) external view returns (uint256 r, uint256 g) {
        g = gasleft();
        unchecked {
            r = (t * (x >> 50) + ((t * (x & POW_FIXED_ONE_TWOS_MASK)) >> 50)) / POW_FIXED_ONE_ODD;
        }
        g -= gasleft();
    }

    function logSixth(uint256 x) internal view {
        uint256 t;
        unchecked {
            uint256 u = x / POW_FIXED_SQRT_ONE;
            uint256 v = x % POW_FIXED_SQRT_ONE;
            t = u * u + (u * v * 2 * POW_FIXED_SQRT_ONE + v * v) / POW_FIXED_ONE;
        }
        (uint256 wide, uint256 wideGas) = this.wideAssembly(t, x);
        (uint256 splitA, uint256 splitAGas) = this.splitAssembly(t, x);
        (uint256 splitS, uint256 splitSGas) = this.splitSolidity(t, x);
        (uint256 shiftA, uint256 shiftAGas) = this.shiftAssembly(t, x);
        (uint256 shiftS, uint256 shiftSGas) = this.shiftSolidity(t, x);
        assertEq(splitA, wide, "split assembly");
        assertEq(splitS, wide, "split solidity");
        assertEq(shiftA, wide, "shift assembly");
        assertEq(shiftS, wide, "shift solidity");
        console2.log("x", x);
        console2.log("  wide assembly ", wideGas);
        console2.log("  split assembly", splitAGas);
        console2.log("  split solidity", splitSGas);
        console2.log("  shift assembly", shiftAGas);
        console2.log("  shift solidity", shiftSGas);
    }

    /// zero, one word of the 1e25 split, and zSquared at `LOG10_RATIO_Z_MAX`.
    function testLog10RatioSixthGas() external view {
        logSixth(0);
        logSixth(1e25 - 1);
        logSixth(1e25);
        logSixth(1e40 + 12345);
        logSixth(56234132519034908039495103977648123146825104);
    }
}
