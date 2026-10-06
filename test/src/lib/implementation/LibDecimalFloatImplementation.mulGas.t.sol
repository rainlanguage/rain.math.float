// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test, console2} from "forge-std-1.17.0/src/Test.sol";

/// Logs the gas of `mul` per input, measured inside the call so ABI overhead
/// is excluded. Run with `-vv` on two trees to compare them.
contract LibDecimalFloatImplementationMulGasTest is Test {
    function implGas(int256 a, int256 ea, int256 b, int256 eb) external view returns (uint256 g) {
        g = gasleft();
        LibDecimalFloatImplementation.mul(a, ea, b, eb);
        g -= gasleft();
    }

    function floatGas(Float a, Float b) external view returns (uint256 g) {
        g = gasleft();
        LibDecimalFloat.mul(a, b);
        g -= gasleft();
    }

    function logImpl(string memory name, int256 a, int256 ea, int256 b, int256 eb) internal view {
        try this.implGas(a, ea, b, eb) returns (uint256 g) {
            console2.log(name, g);
        } catch {
            console2.log(name, "reverted");
        }
    }

    function logPacked(string memory name, int256 a, int256 ea, int256 b, int256 eb) internal view {
        logImpl(string.concat("impl  ", name), a, ea, b, eb);
        Float fa = LibDecimalFloat.packLossless(a, ea);
        Float fb = LibDecimalFloat.packLossless(b, eb);
        console2.log(string.concat("float ", name), this.floatGas(fa, fb));
    }

    function testMulGasPacked() external view {
        int256 c224Max = type(int224).max;
        int256 c224Min = type(int224).min;
        int256 e32Max = type(int32).max;
        int256 e32Min = type(int32).min;
        logPacked("1e0 * 1e0", 1, 0, 1, 0);
        logPacked("1e37e-37 * 1e37e-37", 1e37, -37, 1e37, -37);
        logPacked("123456789e-5 * 987654321e-3", 123456789, -5, 987654321, -3);
        logPacked("-5e2 * 3e-1", -5, 2, 3, -1);
        logPacked("7e5 * 11e0", 7, 5, 11, 0);
        logPacked("-99e-2 * -99e7", -99, -2, -99, 7);
        logPacked("1e18e-18 * -15e17e-18", 1e18, -18, -15e17, -18);
        logPacked("int224.max * int224.max", c224Max, 0, c224Max, 0);
        logPacked("int224.min e-10 * int224.max e3", c224Min, -10, c224Max, 3);
        logPacked("2e(int32.max/2) * 3e(int32.max/2)", 2, e32Max / 2, 3, e32Max / 2);
        logPacked("-2e(int32.min/2) * 3e(int32.min/2)", -2, e32Min / 2, 3, e32Min / 2);
        logPacked("int224.max e(int32.min) * -7e(int32.max)", c224Max, e32Min, -7, e32Max);
    }

    function testMulGasNearCeiling() external view {
        int256 m = type(int256).max;
        logImpl("ceil 1e(max-100) * 1e50", 1, m - 100, 1, 50);
        logImpl("ceil 1e(max-78) * 1e0", 1, m - 78, 1, 0);
        logImpl("ceil 1e(max-1) * 1e-5", 1, m - 1, 1, -5);
        logImpl("ceil int224.max e(max-100) * int224.max e0", type(int224).max, m - 100, type(int224).max, 0);
        logImpl("ceil 1e(max) * 1e1", 1, m, 1, 1);
        logImpl("floor 1e(min) * 1e-1", 1, type(int256).min, 1, -1);
    }
}
