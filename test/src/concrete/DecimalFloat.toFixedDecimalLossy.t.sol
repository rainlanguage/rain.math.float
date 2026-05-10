// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LogTest} from "test/abstract/LogTest.sol";
import {DecimalFloat} from "src/concrete/DecimalFloat.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {FixedDecimalOverflow} from "src/error/ErrDecimalFloat.sol";

contract DecimalFloatToFixedDecimalLossyTest is LogTest {
    using LibDecimalFloat for Float;

    function toFixedDecimalLossyExternal(Float packed, uint8 decimals) external pure returns (uint256, bool) {
        return LibDecimalFloat.toFixedDecimalLossy(packed, decimals);
    }

    /// `toFixedDecimalLossy` reverts with `FixedDecimalOverflow` instead of
    /// `Panic(0x11)` when the positive-exponent scaling would overflow
    /// uint256. Two distinct overflow paths: `10 ** finalExponent` itself
    /// (exponent > 77) and `coefficient * scale` (coefficient too large for
    /// the chosen scale). Reverting rather than returning a silent zero
    /// avoids decapitating the high bits of a real value.
    function testToFixedDecimalLossyPositiveExponentScaleOverflow() external {
        Float aboveScaleLimit = LibDecimalFloat.packLossless(1, 78);
        vm.expectRevert(abi.encodeWithSelector(FixedDecimalOverflow.selector, int256(1), int256(78), uint8(0)));
        this.toFixedDecimalLossyExternal(aboveScaleLimit, 0);
    }

    function testToFixedDecimalLossyPositiveExponentMulOverflow() external {
        Float coefficientOverflowsScale = LibDecimalFloat.packLossless(type(int224).max, 50);
        vm.expectRevert(
            abi.encodeWithSelector(FixedDecimalOverflow.selector, int256(type(int224).max), int256(50), uint8(0))
        );
        this.toFixedDecimalLossyExternal(coefficientOverflowsScale, 0);
    }

    function testToFixedDecimalLossyDeployed(Float packed, uint8 decimals) external {
        DecimalFloat deployed = new DecimalFloat();

        try this.toFixedDecimalLossyExternal(packed, decimals) returns (uint256 fixedDecimal, bool lossless) {
            (uint256 deployedFixedDecimal, bool deployedLossless) = deployed.toFixedDecimalLossy(packed, decimals);

            assertEq(fixedDecimal, deployedFixedDecimal);
            assertEq(lossless, deployedLossless);
        } catch (bytes memory err) {
            vm.expectRevert(err);
            deployed.toFixedDecimalLossy(packed, decimals);
        }
    }
}
