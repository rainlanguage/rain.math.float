// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {Test, console2} from "forge-std-1.17.0/src/Test.sol";

/// Logs the gas of one `packLossy` per input class, for comparison across
/// revisions. A revert logs the gas of the reverting external call instead.
contract LibDecimalFloatPackLossyGasTest is Test {
    function packLossyGas(int256 c, int256 e) external view returns (Float float, bool lossless, uint256 gasUsed) {
        uint256 before = gasleft();
        (float, lossless) = LibDecimalFloat.packLossy(c, e);
        gasUsed = before - gasleft();
    }

    function measure(string memory name, int256 c, int256 e) internal view returns (Float, bool) {
        uint256 before = gasleft();
        try this.packLossyGas(c, e) returns (Float float, bool lossless, uint256 gasUsed) {
            console2.log(name, gasUsed);
            return (float, lossless);
        } catch {
            console2.log(name, "reverts, external call gas", before - gasleft());
            // forge-lint: disable-next-line(boolean-cst)
            return (LibDecimalFloat.FLOAT_ZERO, false);
        }
    }

    function check(string memory name, int256 c, int256 e, int256 expectedC, int256 expectedE, bool expectedLossless)
        internal
        view
    {
        (Float float, bool lossless) = measure(name, c, e);
        (int256 actualC, int256 actualE) = LibDecimalFloat.unpack(float);
        assertEq(actualC, expectedC, "coefficient");
        assertEq(actualE, expectedE, "exponent");
        assertEq(lossless, expectedLossless, "lossless");
    }

    function testPackLossyGasPacked() external view {
        check("packed 1e0", 1, 0, 1, 0, true);
        check("packed int224.max e-18", type(int224).max, -18, type(int224).max, -18, true);
        check("packed -5 at int32.max", -5, type(int32).max, -5, type(int32).max, true);
        check(
            "packed int224.min at int32.min", type(int224).min, type(int32).min, type(int224).min, type(int32).min, true
        );
        check("zero above the ceiling", 0, int256(type(int32).max) + 1, 0, 0, true);
    }

    function testPackLossyGasLift() external view {
        check("lift 1 by 1", 1, int256(type(int32).max) + 1, 10, type(int32).max, true);
        check("lift 1 by 67", 1, int256(type(int32).max) + 67, 1e67, type(int32).max, true);
        check(
            "lift int224.max/10 by 1",
            type(int224).max / 10,
            int256(type(int32).max) + 1,
            // forge-lint: disable-next-line(divide-before-multiply)
            (type(int224).max / 10) * 10,
            type(int32).max,
            true
        );
    }

    function testPackLossyGasShed() external view {
        check("shed 1e70 + 1", 1e70 + 1, 0, 1e67, 3, false);
        check("shed int256.max", type(int256).max, 0, type(int256).max / 1e10, 10, false);
        check("shed to floor 15 at int32.min - 1", 15, int256(type(int32).min) - 1, 1, type(int32).min, false);
        check("underflow 1 at int32.min - 1", 1, int256(type(int32).min) - 1, 0, 0, false);
    }

    function testPackLossyGasReverts() external view {
        measure("revert int224.max by 1", type(int224).max, int256(type(int32).max) + 1);
        measure("revert 1 by 68", 1, int256(type(int32).max) + 68);
        measure("revert shed past ceiling", type(int256).max, type(int32).max);
    }
}
