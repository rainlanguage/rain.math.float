// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, console2} from "forge-std-1.17.0/src/Test.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";

/// Logs the gas of packed log10 on each `log10Ratio` path.
contract LibDecimalFloatLog10GasTest is Test {
    using LibDecimalFloat for Float;

    function log10Gas(Float float) external view returns (Float result, uint256 gas) {
        gas = gasleft();
        result = float.log10(address(0));
        gas -= gasleft();
    }

    function logGas(string memory label, int256 signedCoefficient, int256 exponent) internal view {
        (, uint256 gas) = this.log10Gas(LibDecimalFloat.packLossless(signedCoefficient, exponent));
        console2.log(label, gas);
    }

    function testLog10Gas() external view {
        logGas("2 (reduced, not relative):", 2, 0);
        logGas("1.0001 (relative):", 10001, -4);
        logGas("0.9999 (relative):", 9999, -4);
        logGas("10.001 (near 10, not relative):", 10001, -3);
        logGas("9.9989e2000000000 (worst reduce):", 99989, 1999999996);
    }
}
