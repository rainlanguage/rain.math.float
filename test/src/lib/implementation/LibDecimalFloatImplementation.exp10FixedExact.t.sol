// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";
import {
    LibDecimalFloatImplementation,
    POW_FIXED_ONE
} from "../../../../src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibExactFloat, ORACLE_ONE} from "../../../lib/LibExactFloat.sol";

contract LibDecimalFloatImplementationExp10FixedExactTest is Test {
    /// 10^(x 1e-50) at 1e50, floored, from the oracle: it is within 1e-67
    /// relative, under 1e-16 of a unit at 1e50, so the floor is exact unless
    /// the power is that close to a unit.
    function truncated(uint256 x) internal pure returns (uint256) {
        // forge-lint: disable-next-line(unsafe-typecast)
        (uint256 power, int256 exponent) = LibExactFloat.exp10(int256(x), -50);
        assertEq(exponent, -70, "exponent");
        return power / (ORACLE_ONE / POW_FIXED_ONE);
    }

    /// Never above the floored power, under 88.08 units and 1.408e-49 of it
    /// below.
    function check(uint256 x) internal pure {
        uint256 actual = LibDecimalFloatImplementation.exp10Fixed(x);
        uint256 floor = truncated(x);
        assertLe(actual, floor, "above");
        assertGe(actual + 88, floor, "below");
        assertGe(actual + Math.mulDiv(floor + 1, 1408, 1e52, Math.Rounding.Ceil), floor, "below relative");
    }

    function testExp10FixedExactFuzz(uint256 x) external pure {
        check(bound(x, 0, POW_FIXED_ONE - 1));
    }

    /// x in [0.5, 0.5 + 2^-16) whose final SQRT10 * series multiply borrows,
    /// and x below 2^-16 whose series * x before adding ln 10 borrows.
    function testExp10FixedExactBorrows() external pure {
        uint256[6] memory xs = [
            uint256(5e49 + 87015477053855611590102368556),
            5e49 + 129156888290026095774709585062,
            5e49 + 430189686290292988458280452418,
            858803594111162378152345370348828441692620967,
            724330556364502386237515770486668923888293239,
            432154281105992271870088449799288377367521809
        ];
        for (uint256 i = 0; i < xs.length; i++) {
            check(xs[i]);
        }
    }

    /// Each binary digit 2^-i, one either side of it, and the sums of the
    /// first i digits, where one more unit of x carries into step i.
    function testExp10FixedExactDigitEdges() external pure {
        uint256 sum = 0;
        for (uint256 i = 1; i <= 16; i++) {
            uint256 digit = POW_FIXED_ONE >> i;
            sum += digit;
            check(digit - 1);
            check(digit);
            check(digit + 1);
            check(sum - 1);
            check(sum);
            check(sum + 1);
        }
    }
}
