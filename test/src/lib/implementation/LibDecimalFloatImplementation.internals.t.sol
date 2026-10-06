// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LogTest} from "test/abstract/LogTest.sol";
import {MulDivOverflow} from "src/error/ErrDecimalFloat.sol";

/// @title Direct tests for internal functions that previously had no dedicated
/// test coverage (audit finding A09-11).
contract LibDecimalFloatImplementationInternalsTest is LogTest {
    // -- absUnsignedSignedCoefficient --

    function testAbsZero() external pure {
        assertEq(LibDecimalFloatImplementation.absUnsignedSignedCoefficient(0), 0);
    }

    function testAbsPositive(int256 x) external pure {
        x = bound(x, 1, type(int256).max);
        // Safe: x is bounded to [1, type(int256).max] so fits in uint256.
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(LibDecimalFloatImplementation.absUnsignedSignedCoefficient(x), uint256(x));
    }

    function testAbsNegative(int256 x) external pure {
        x = bound(x, type(int256).min + 1, -1);
        // Safe: x is negative so -x is positive and fits in uint256.
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(LibDecimalFloatImplementation.absUnsignedSignedCoefficient(x), uint256(-x));
    }

    function testAbsMinInt256() external pure {
        // type(int256).min has no positive counterpart in int256, but fits in uint256.
        assertEq(
            LibDecimalFloatImplementation.absUnsignedSignedCoefficient(type(int256).min), uint256(type(int256).max) + 1
        );
    }

    // -- mul512 --

    function testMul512Zero() external pure {
        (uint256 high, uint256 low) = LibDecimalFloatImplementation.mul512(0, 12345);
        assertEq(high, 0);
        assertEq(low, 0);
    }

    function testMul512NoOverflow(uint128 a, uint128 b) external pure {
        (uint256 high, uint256 low) = LibDecimalFloatImplementation.mul512(uint256(a), uint256(b));
        assertEq(high, 0);
        assertEq(low, uint256(a) * uint256(b));
    }

    function testMul512MaxValues() external pure {
        // type(uint256).max * type(uint256).max should produce a 512-bit result.
        (uint256 high, uint256 low) = LibDecimalFloatImplementation.mul512(type(uint256).max, type(uint256).max);
        // (2^256 - 1)^2 = 2^512 - 2^257 + 1
        // high = 2^256 - 2 = type(uint256).max - 1
        // low = 1
        assertEq(high, type(uint256).max - 1);
        assertEq(low, 1);
    }

    // -- mulDiv --

    function testMulDivSimple() external pure {
        // 6 * 7 / 3 = 14
        assertEq(LibDecimalFloatImplementation.mulDiv(6, 7, 3), 14);
    }

    function testMulDivLargeNumerator() external pure {
        // Test with values that overflow uint256 in intermediate multiplication.
        uint256 x = type(uint256).max;
        uint256 y = 2;
        uint256 d = 2;
        // (max * 2) / 2 = max
        assertEq(LibDecimalFloatImplementation.mulDiv(x, y, d), type(uint256).max);
    }

    function mulDivExternal(uint256 x, uint256 y, uint256 d) external pure returns (uint256) {
        return LibDecimalFloatImplementation.mulDiv(x, y, d);
    }

    function testMulDivOverflowReverts() external {
        // Result would be type(uint256).max^2 which exceeds uint256.
        vm.expectRevert(abi.encodeWithSelector(MulDivOverflow.selector, type(uint256).max, type(uint256).max, 1));
        this.mulDivExternal(type(uint256).max, type(uint256).max, 1);
    }

    // -- compareRescale --

    function testCompareRescaleSameExponent() external pure {
        (int256 a, int256 b) = LibDecimalFloatImplementation.compareRescale(5, 0, 3, 0);
        assertEq(a, 5);
        assertEq(b, 3);
    }

    function testCompareRescaleDifferentExponents() external pure {
        // 5e2 vs 3e3 => rescale to compare: 5 vs 30
        (int256 a, int256 b) = LibDecimalFloatImplementation.compareRescale(5, 2, 3, 3);
        // After rescaling, a < b should hold (500 < 3000)
        assertTrue(a < b);
    }

    function testCompareRescaleEqual() external pure {
        // 50e1 vs 5e2 are equal (both 500)
        (int256 a, int256 b) = LibDecimalFloatImplementation.compareRescale(50, 1, 5, 2);
        assertEq(a, b);
    }
}
