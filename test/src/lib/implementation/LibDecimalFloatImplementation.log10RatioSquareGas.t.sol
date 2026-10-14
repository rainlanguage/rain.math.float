// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    POW_FIXED_ONE,
    POW_FIXED_SQRT_ONE,
    POW_FIXED_TWO_SQRT_ONE,
    POW_FIXED_ONE_ODD_INVERSE
} from "../../../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Test, console2} from "forge-std-1.17.0/src/Test.sol";

/// Logs the gas of `log10Ratio`'s z^4 step, floor(x^2 / 1e50) for x its
/// zSquared, three ways, inside the call so ABI overhead is excluded: the
/// in-place 512-bit `mulDivFixed` it replaced, and the 1e25 split it uses,
/// in assembly and in plain Solidity. Run with `-vv`.
contract LibDecimalFloatImplementationLog10RatioSquareGasTest is Test {
    function wideAssembly(uint256 x) external view returns (uint256 r, uint256 g) {
        uint256 inverse = POW_FIXED_ONE_ODD_INVERSE;
        g = gasleft();
        assembly ("memory-safe") {
            let mm := mulmod(x, x, not(0))
            let prod0 := mul(x, x)
            let remainder := mulmod(x, x, POW_FIXED_ONE)
            r := mul(
                or(
                    shr(50, sub(prod0, remainder)),
                    shl(206, sub(sub(sub(mm, prod0), lt(mm, prod0)), gt(remainder, prod0)))
                ),
                inverse
            )
        }
        g -= gasleft();
    }

    function splitAssembly(uint256 x) external view returns (uint256 r, uint256 g) {
        g = gasleft();
        assembly ("memory-safe") {
            let u := div(x, POW_FIXED_SQRT_ONE)
            let v := mod(x, POW_FIXED_SQRT_ONE)
            r := add(mul(u, u), div(add(mul(mul(u, v), POW_FIXED_TWO_SQRT_ONE), mul(v, v)), POW_FIXED_ONE))
        }
        g -= gasleft();
    }

    function splitSolidity(uint256 x) external view returns (uint256 r, uint256 g) {
        g = gasleft();
        unchecked {
            uint256 u = x / POW_FIXED_SQRT_ONE;
            uint256 v = x % POW_FIXED_SQRT_ONE;
            r = u * u + (u * v * POW_FIXED_TWO_SQRT_ONE + v * v) / POW_FIXED_ONE;
        }
        g -= gasleft();
    }

    function logSquare(uint256 x) internal view {
        (uint256 wide, uint256 wideGas) = this.wideAssembly(x);
        (uint256 splitA, uint256 splitAGas) = this.splitAssembly(x);
        (uint256 splitS, uint256 splitSGas) = this.splitSolidity(x);
        assertEq(splitA, wide, "split assembly");
        assertEq(splitS, wide, "split solidity");
        console2.log("x", x);
        console2.log("  wide assembly ", wideGas);
        console2.log("  split assembly", splitAGas);
        console2.log("  split solidity", splitSGas);
    }

    /// zero, one word of the split, and zSquared at `LOG10_RATIO_Z_MAX`.
    function testLog10RatioSquareGas() external view {
        logSquare(0);
        logSquare(1e25 - 1);
        logSquare(1e25);
        logSquare(1e40 + 12345);
        logSquare(56234132519034908039495103977648123146825104);
    }
}
